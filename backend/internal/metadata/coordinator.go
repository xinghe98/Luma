// Metadata coordination ranks provider-neutral candidates and normalizes selected work details.
package metadata

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"unicode"

	"github.com/xinghe98/Luma/backend/internal/catalog"
	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

// ErrNoOnlineProvider means no registered provider can search the requested work kind.
var ErrNoOnlineProvider = errors.New("no online metadata provider")

// ResolveOutcome contains either one confirmed metadata result or manual candidates.
type ResolveOutcome struct {
	Result     *domain.CatalogMetadataResult
	Candidates []domain.CatalogMetadataCandidate
}

// Coordinator applies Luma matching policy to registered provider results.
type Coordinator struct {
	registry  *Registry
	locale    scraper.Locale
	threshold int
	margin    int
}

// NewCoordinator creates the provider-neutral matching coordinator.
func NewCoordinator(registry *Registry, locale scraper.Locale, threshold, margin int) (*Coordinator, error) {
	if registry == nil || threshold < 0 || threshold > 100 || margin < 0 || margin > 100 {
		return nil, errors.New("元数据协调器配置无效")
	}
	return &Coordinator{registry: registry, locale: locale, threshold: threshold, margin: margin}, nil
}

// Resolve fetches a locked identity directly or searches and conservatively confirms one candidate.
func (c *Coordinator) Resolve(ctx context.Context, input domain.CatalogScrapeInput, patches ...scraper.MetadataPatch) (ResolveOutcome, error) {
	kind := scraper.MediaKind(input.Kind)
	patch := mergePatches(patches)
	hadExplicitIdentity := input.Provider != "" && input.ProviderItemID != ""
	if patch.Title != nil {
		input.Title = *patch.Title
	}
	if patch.Year != nil {
		input.Year = patch.Year
	}
	if input.Provider == "" {
		keys := sortedExternalIDKeys(patch.ExternalIDs)
		for _, providerID := range keys {
			if _, ok := c.registry.Provider(providerID); ok {
				input.Provider, input.ProviderItemID = providerID, patch.ExternalIDs[providerID]
				break
			}
		}
	}
	if input.Provider != "" && input.ProviderItemID != "" {
		provider, ok := c.registry.Provider(input.Provider)
		if !ok {
			if !hadExplicitIdentity && patch.Title != nil {
				result := resultFromPatch(input.ItemID, patch)
				return ResolveOutcome{Result: &result}, nil
			}
			return ResolveOutcome{}, fmt.Errorf("%w: %s", ErrNoOnlineProvider, input.Provider)
		}
		fetcher, ok := provider.(scraper.WorkFetcher)
		if !ok {
			return ResolveOutcome{}, &scraper.ProviderError{
				ProviderID: input.Provider, Operation: "fetch_work", Kind: scraper.ErrorUnsupported,
			}
		}
		value, err := fetcher.FetchWork(ctx, scraper.WorkRequest{
			Kind: kind, ProviderItemID: input.ProviderItemID, Locale: c.locale,
		})
		if err != nil {
			return ResolveOutcome{}, err
		}
		result, err := resultFromWork(input.ItemID, value)
		applyPatch(&result, patch)
		return ResolveOutcome{Result: &result}, err
	}

	var externallyResolved []scraper.Candidate
	for _, source := range sortedExternalIDKeys(patch.ExternalIDs) {
		for _, provider := range c.registry.ProvidersFor(kind, scraper.CapabilityExternalID) {
			resolved, err := provider.(scraper.ExternalIDResolver).ResolveExternalID(ctx, scraper.ExternalIDRequest{
				Kind: kind, Source: source, Value: patch.ExternalIDs[source], Locale: c.locale,
			})
			var providerErr *scraper.ProviderError
			if errors.As(err, &providerErr) && providerErr.Kind == scraper.ErrorUnsupported {
				continue
			}
			if err != nil {
				return ResolveOutcome{}, err
			}
			externallyResolved = append(externallyResolved, resolved...)
		}
	}
	externallyResolved = uniqueCandidates(externallyResolved)
	if len(externallyResolved) == 1 {
		result, err := c.fetchCandidate(ctx, input.ItemID, kind, externallyResolved[0])
		if err != nil {
			return ResolveOutcome{}, err
		}
		applyPatch(&result, patch)
		return ResolveOutcome{Result: &result}, nil
	}

	providers := c.registry.ProvidersFor(kind, scraper.CapabilitySearch)
	if len(providers) == 0 && len(externallyResolved) == 0 {
		if patch.Title != nil {
			result := resultFromPatch(input.ItemID, patch)
			return ResolveOutcome{Result: &result}, nil
		}
		return ResolveOutcome{}, ErrNoOnlineProvider
	}
	candidates := make([]scoredCandidate, 0, len(externallyResolved)+10)
	for _, value := range externallyResolved {
		score, reasons := scoreCandidate(input, value)
		candidates = append(candidates, scoredCandidate{candidate: value, score: score, reasons: append(reasons, "外部 ID 匹配")})
	}
	for _, provider := range providers {
		searcher := provider.(scraper.Searcher)
		page, err := searcher.Search(ctx, scraper.SearchRequest{
			Kind: kind, Query: input.Title, Year: input.Year, Locale: c.locale, Limit: 10,
		})
		if err != nil {
			return ResolveOutcome{}, err
		}
		for _, value := range page.Items {
			score, reasons := scoreCandidate(input, value)
			candidates = append(candidates, scoredCandidate{candidate: value, score: score, reasons: reasons})
		}
	}
	sortCandidates(candidates)
	persisted := make([]domain.CatalogMetadataCandidate, 0, len(candidates))
	for _, value := range candidates {
		persisted = append(persisted, domain.CatalogMetadataCandidate{
			ID:     catalog.StableID("candidate", input.ItemID, value.candidate.ProviderID, value.candidate.ProviderItemID),
			ItemID: input.ItemID, Provider: value.candidate.ProviderID,
			ProviderItemID: value.candidate.ProviderItemID, Title: value.candidate.Title,
			OriginalTitle: value.candidate.OriginalTitle, Year: yearFromDate(value.candidate.ReleaseDate),
			Overview: value.candidate.Overview, Score: value.score, Reasons: value.reasons,
			PosterRef: artworkKey(value.candidate.Poster),
		})
	}
	if len(candidates) == 0 || candidates[0].score < c.threshold ||
		(len(candidates) > 1 && candidates[0].score-candidates[1].score < c.margin) {
		return ResolveOutcome{Candidates: persisted}, nil
	}
	selected := candidates[0].candidate
	provider, ok := c.registry.Provider(selected.ProviderID)
	if !ok {
		return ResolveOutcome{}, ErrNoOnlineProvider
	}
	fetcher, ok := provider.(scraper.WorkFetcher)
	if !ok {
		return ResolveOutcome{}, &scraper.ProviderError{
			ProviderID: selected.ProviderID, Operation: "fetch_work", Kind: scraper.ErrorUnsupported,
		}
	}
	work, err := fetcher.FetchWork(ctx, scraper.WorkRequest{
		Kind: kind, ProviderItemID: selected.ProviderItemID, Locale: c.locale,
	})
	if err != nil {
		return ResolveOutcome{}, err
	}
	result, err := resultFromWork(input.ItemID, work)
	if err != nil {
		return ResolveOutcome{}, err
	}
	applyPatch(&result, patch)
	return ResolveOutcome{Result: &result}, nil
}

func (c *Coordinator) fetchCandidate(ctx context.Context, itemID string, kind scraper.MediaKind,
	candidate scraper.Candidate) (domain.CatalogMetadataResult, error) {
	provider, ok := c.registry.Provider(candidate.ProviderID)
	if !ok {
		return domain.CatalogMetadataResult{}, ErrNoOnlineProvider
	}
	fetcher, ok := provider.(scraper.WorkFetcher)
	if !ok {
		return domain.CatalogMetadataResult{}, &scraper.ProviderError{
			ProviderID: candidate.ProviderID, Operation: "fetch_work", Kind: scraper.ErrorUnsupported,
		}
	}
	work, err := fetcher.FetchWork(ctx, scraper.WorkRequest{
		Kind: kind, ProviderItemID: candidate.ProviderItemID, Locale: c.locale,
	})
	if err != nil {
		return domain.CatalogMetadataResult{}, err
	}
	return resultFromWork(itemID, work)
}

// ParseSidecar routes an already opened sidecar through the first matching registered parser.
func (c *Coordinator) ParseSidecar(ctx context.Context, request scraper.SidecarRequest) (scraper.MetadataPatch, error) {
	providers := c.registry.ProvidersFor(request.Kind, scraper.CapabilitySidecar)
	if len(providers) == 0 {
		return scraper.MetadataPatch{}, ErrNoOnlineProvider
	}
	return providers[0].(scraper.SidecarParser).ParseSidecar(ctx, request)
}

type scoredCandidate struct {
	candidate scraper.Candidate
	score     int
	reasons   []string
}

func scoreCandidate(input domain.CatalogScrapeInput, value scraper.Candidate) (int, []string) {
	score := 0
	var reasons []string
	source := normalize(input.Title)
	best := 0
	titles := append([]string{value.Title, value.OriginalTitle}, value.AlternativeTitles...)
	for _, title := range titles {
		candidate := normalize(title)
		if candidate == "" {
			continue
		}
		current := similarityScore(source, candidate)
		if current > best {
			best = current
		}
	}
	score += best
	switch {
	case best == 60:
		reasons = append(reasons, "标题完全匹配")
	case best >= 48:
		reasons = append(reasons, "标题高度相似")
	case best > 0:
		reasons = append(reasons, "标题部分相似")
	}
	candidateYear := yearFromDate(value.ReleaseDate)
	if input.Year == nil {
		score += 10
		reasons = append(reasons, "文件名未提供年份")
	} else if candidateYear != nil && *candidateYear == *input.Year {
		score += 20
		reasons = append(reasons, "年份一致")
	} else if candidateYear != nil && abs(*candidateYear-*input.Year) == 1 {
		score += 10
		reasons = append(reasons, "年份相差一年")
	} else if candidateYear != nil {
		reasons = append(reasons, "年份冲突")
	}
	// Search responses do not include runtime; five points are neutral until details are fetched.
	score += 5
	// The catalog hint is already the strongest parent/file consensus selected by the naming parser.
	score += 10
	return min(score, 100), reasons
}

func similarityScore(left, right string) int {
	if left == right {
		return 60
	}
	if strings.Contains(left, right) || strings.Contains(right, left) {
		return 50
	}
	distance := levenshtein([]rune(left), []rune(right))
	longest := max(len([]rune(left)), len([]rune(right)))
	if longest == 0 {
		return 0
	}
	ratio := 1 - float64(distance)/float64(longest)
	return int(math.Round(max(0, ratio) * 45))
}

func normalize(value string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return unicode.ToLower(r)
		}
		return -1
	}, value)
}

func levenshtein(left, right []rune) int {
	previous := make([]int, len(right)+1)
	for index := range previous {
		previous[index] = index
	}
	for i, a := range left {
		current := make([]int, len(right)+1)
		current[0] = i + 1
		for j, b := range right {
			cost := 0
			if a != b {
				cost = 1
			}
			current[j+1] = min(current[j]+1, previous[j+1]+1, previous[j]+cost)
		}
		previous = current
	}
	return previous[len(right)]
}

func sortCandidates(values []scoredCandidate) {
	for i := 1; i < len(values); i++ {
		for j := i; j > 0; j-- {
			left, right := values[j-1], values[j]
			if left.score > right.score ||
				(left.score == right.score && left.candidate.Popularity >= right.candidate.Popularity) {
				break
			}
			values[j-1], values[j] = values[j], values[j-1]
		}
	}
}

func sortedExternalIDKeys(values map[string]string) []string {
	keys := make([]string, 0, len(values))
	for key, value := range values {
		if strings.TrimSpace(key) != "" && strings.TrimSpace(value) != "" {
			keys = append(keys, strings.ToLower(strings.TrimSpace(key)))
		}
	}
	sort.Strings(keys)
	return keys
}

func uniqueCandidates(values []scraper.Candidate) []scraper.Candidate {
	result := make([]scraper.Candidate, 0, len(values))
	seen := map[string]struct{}{}
	for _, value := range values {
		key := value.ProviderID + "\x00" + value.ProviderItemID
		if value.ProviderID == "" || value.ProviderItemID == "" {
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, value)
	}
	return result
}

func resultFromWork(itemID string, value scraper.WorkMetadata) (domain.CatalogMetadataResult, error) {
	if value.ProviderID == "" || value.ProviderItemID == "" || value.Title == "" {
		return domain.CatalogMetadataResult{}, errors.New("provider returned incomplete work identity")
	}
	genres, err := json.Marshal(value.Genres)
	if err != nil {
		return domain.CatalogMetadataResult{}, err
	}
	countries, _ := json.Marshal(value.Countries)
	studios, _ := json.Marshal(value.Studios)
	credits, _ := json.Marshal(value.Credits)
	externalIDs := value.ExternalIDs
	if externalIDs == nil {
		externalIDs = map[string]string{}
	}
	externalIDs[value.ProviderID] = value.ProviderItemID
	external, _ := json.Marshal(externalIDs)
	var runtimeMS *int64
	if value.Runtime != nil {
		milliseconds := value.Runtime.Milliseconds()
		runtimeMS = &milliseconds
	}
	return domain.CatalogMetadataResult{
		ItemID: itemID, Provider: value.ProviderID, ProviderItemID: value.ProviderItemID,
		Title: value.Title, OriginalTitle: value.OriginalTitle, Year: yearFromDate(value.ReleaseDate),
		AlternativeTitles: value.AlternativeTitles, Overview: value.Overview, Tagline: value.Tagline,
		ReleaseDate: value.ReleaseDate, EndDate: value.EndDate, RuntimeMS: runtimeMS,
		Certification: value.Certification, CommunityRating: value.CommunityRating, VoteCount: value.VoteCount,
		GenresJSON: string(genres), CountriesJSON: string(countries), StudiosJSON: string(studios),
		CreditsJSON: string(credits), ExternalIDsJSON: string(external),
		PosterRef: artworkKey(value.Poster), BackdropRef: artworkKey(value.Backdrop),
	}, nil
}

func mergePatches(values []scraper.MetadataPatch) scraper.MetadataPatch {
	var result scraper.MetadataPatch
	for _, value := range values {
		if value.Title != nil {
			result.Title = value.Title
		}
		if value.OriginalTitle != nil {
			result.OriginalTitle = value.OriginalTitle
		}
		if value.Overview != nil {
			result.Overview = value.Overview
		}
		if value.Tagline != nil {
			result.Tagline = value.Tagline
		}
		if value.ReleaseDate != nil {
			result.ReleaseDate = value.ReleaseDate
		}
		if value.Year != nil {
			result.Year = value.Year
		}
		if value.Runtime != nil {
			result.Runtime = value.Runtime
		}
		if value.Certification != nil {
			result.Certification = value.Certification
		}
		if value.CommunityRating != nil {
			result.CommunityRating = value.CommunityRating
		}
		if value.Genres != nil {
			result.Genres = value.Genres
		}
		if value.ExternalIDs != nil {
			if result.ExternalIDs == nil {
				result.ExternalIDs = map[string]string{}
			}
			for key, id := range value.ExternalIDs {
				result.ExternalIDs[strings.ToLower(strings.TrimSpace(key))] = strings.TrimSpace(id)
			}
		}
		if value.Poster != nil {
			result.Poster = value.Poster
		}
		if value.Backdrop != nil {
			result.Backdrop = value.Backdrop
		}
	}
	return result
}

func applyPatch(result *domain.CatalogMetadataResult, patch scraper.MetadataPatch) {
	if patch.Title != nil {
		result.Title = *patch.Title
	}
	if patch.OriginalTitle != nil {
		result.OriginalTitle = *patch.OriginalTitle
	}
	if patch.Overview != nil {
		result.Overview = *patch.Overview
	}
	if patch.Tagline != nil {
		result.Tagline = *patch.Tagline
	}
	if patch.ReleaseDate != nil {
		result.ReleaseDate = *patch.ReleaseDate
	}
	if patch.Year != nil {
		result.Year = patch.Year
	}
	if patch.Runtime != nil {
		value := patch.Runtime.Milliseconds()
		result.RuntimeMS = &value
	}
	if patch.Certification != nil {
		result.Certification = *patch.Certification
	}
	if patch.CommunityRating != nil {
		result.CommunityRating = patch.CommunityRating
	}
	if patch.Genres != nil {
		data, _ := json.Marshal(*patch.Genres)
		result.GenresJSON = string(data)
	}
	if len(patch.ExternalIDs) > 0 {
		ids := map[string]string{}
		_ = json.Unmarshal([]byte(result.ExternalIDsJSON), &ids)
		for key, value := range patch.ExternalIDs {
			ids[key] = value
		}
		data, _ := json.Marshal(ids)
		result.ExternalIDsJSON = string(data)
	}
	if patch.Poster != nil {
		result.PosterRef = patch.Poster.Key
	}
	if patch.Backdrop != nil {
		result.BackdropRef = patch.Backdrop.Key
	}
}

func resultFromPatch(itemID string, patch scraper.MetadataPatch) domain.CatalogMetadataResult {
	result := domain.CatalogMetadataResult{
		ItemID: itemID, Provider: "nfo", ProviderItemID: itemID,
		GenresJSON: "[]", CountriesJSON: "[]", StudiosJSON: "[]", CreditsJSON: "[]", ExternalIDsJSON: "{}",
	}
	applyPatch(&result, patch)
	return result
}

func artworkKey(value *scraper.ArtworkRef) string {
	if value == nil {
		return ""
	}
	return value.Key
}

func yearFromDate(value string) *int {
	if len(value) < 4 {
		return nil
	}
	year, err := strconv.Atoi(value[:4])
	if err != nil || year < 1800 || year > 3000 {
		return nil
	}
	return &year
}

func abs(value int) int {
	if value < 0 {
		return -value
	}
	return value
}
