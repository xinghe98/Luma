// Package tmdb implements the TMDb v3 scraper provider behind Luma's public scraper contract.
// It owns TMDb HTTP and JSON shapes; callers receive only provider-neutral metadata.
package tmdb

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

const providerID = "tmdb"

// Options contains the implementation-private TMDb configuration.
type Options struct {
	AccessToken  string
	APIBaseURL   string
	ImageBaseURL string
}

// Provider implements movie, series, season, episode, artwork, and health operations.
type Provider struct {
	options Options
	client  *http.Client
}

var (
	_ scraper.Searcher           = (*Provider)(nil)
	_ scraper.ExternalIDResolver = (*Provider)(nil)
	_ scraper.WorkFetcher        = (*Provider)(nil)
	_ scraper.SeasonFetcher      = (*Provider)(nil)
	_ scraper.EpisodeFetcher     = (*Provider)(nil)
	_ scraper.ArtworkFetcher     = (*Provider)(nil)
	_ scraper.HealthChecker      = (*Provider)(nil)
)

// New validates raw provider options and creates a TMDb provider using the injected client.
func New(raw map[string]any, client *http.Client) (*Provider, error) {
	if client == nil {
		return nil, errors.New("TMDb HTTP client is required")
	}
	allowed := map[string]bool{"access_token": true, "api_base_url": true, "image_base_url": true}
	for key := range raw {
		if !allowed[key] {
			return nil, fmt.Errorf("unknown TMDb option %q", key)
		}
	}
	options := Options{
		AccessToken:  stringOption(raw, "access_token"),
		APIBaseURL:   stringOption(raw, "api_base_url"),
		ImageBaseURL: stringOption(raw, "image_base_url"),
	}
	if options.APIBaseURL == "" {
		options.APIBaseURL = "https://api.themoviedb.org/3"
	}
	if options.ImageBaseURL == "" {
		options.ImageBaseURL = "https://image.tmdb.org/t/p/original"
	}
	if strings.TrimSpace(options.AccessToken) == "" {
		return nil, errors.New("TMDb options.access_token is required when enabled")
	}
	for name, value := range map[string]string{"api_base_url": options.APIBaseURL, "image_base_url": options.ImageBaseURL} {
		parsed, err := url.Parse(value)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return nil, fmt.Errorf("TMDb %s must be an absolute HTTPS URL", name)
		}
	}
	options.APIBaseURL = strings.TrimRight(options.APIBaseURL, "/")
	options.ImageBaseURL = strings.TrimRight(options.ImageBaseURL, "/")
	return &Provider{options: options, client: client}, nil
}

// Descriptor declares all TMDb capabilities used by Luma.
func (*Provider) Descriptor() scraper.Descriptor {
	return scraper.Descriptor{
		ID: providerID, Name: "The Movie Database",
		Kinds: []scraper.MediaKind{scraper.MediaKindMovie, scraper.MediaKindSeries},
		Capabilities: []scraper.Capability{
			scraper.CapabilitySearch, scraper.CapabilityExternalID, scraper.CapabilityWork,
			scraper.CapabilitySeason, scraper.CapabilityEpisode, scraper.CapabilityArtwork,
			scraper.CapabilityHealth,
		},
	}
}

type searchResponse struct {
	Results []searchItem `json:"results"`
}

type searchItem struct {
	ID            int64   `json:"id"`
	Title         string  `json:"title"`
	Name          string  `json:"name"`
	OriginalTitle string  `json:"original_title"`
	OriginalName  string  `json:"original_name"`
	ReleaseDate   string  `json:"release_date"`
	FirstAirDate  string  `json:"first_air_date"`
	Overview      string  `json:"overview"`
	Popularity    float64 `json:"popularity"`
	PosterPath    string  `json:"poster_path"`
	BackdropPath  string  `json:"backdrop_path"`
	MediaType     string  `json:"media_type"`
}

// Search queries translated and alternative titles for the requested media kind.
func (p *Provider) Search(ctx context.Context, request scraper.SearchRequest) (scraper.SearchPage, error) {
	path := "/search/movie"
	if request.Kind == scraper.MediaKindSeries {
		path = "/search/tv"
	}
	query := url.Values{"query": []string{request.Query}, "language": []string{language(request.Locale)}}
	if request.Year != nil {
		if request.Kind == scraper.MediaKindSeries {
			query.Set("first_air_date_year", strconv.Itoa(*request.Year))
		} else {
			query.Set("primary_release_year", strconv.Itoa(*request.Year))
		}
	}
	var response searchResponse
	if err := p.getJSON(ctx, path, query, &response); err != nil {
		return scraper.SearchPage{}, err
	}
	limit := request.Limit
	if limit <= 0 || limit > 20 {
		limit = 10
	}
	if len(response.Results) > limit {
		response.Results = response.Results[:limit]
	}
	items := make([]scraper.Candidate, 0, len(response.Results))
	for _, item := range response.Results {
		items = append(items, candidateFromSearch(request.Kind, item))
	}
	return scraper.SearchPage{Items: items}, nil
}

// ResolveExternalID maps IMDb or TVDb IDs through TMDb's find endpoint.
func (p *Provider) ResolveExternalID(ctx context.Context, request scraper.ExternalIDRequest) ([]scraper.Candidate, error) {
	source := map[string]string{"imdb": "imdb_id", "tvdb": "tvdb_id"}[strings.ToLower(request.Source)]
	if source == "" {
		return nil, &scraper.ProviderError{ProviderID: providerID, Operation: "resolve_external_id", Kind: scraper.ErrorUnsupported}
	}
	var response struct {
		MovieResults []searchItem `json:"movie_results"`
		TVResults    []searchItem `json:"tv_results"`
	}
	query := url.Values{"external_source": []string{source}, "language": []string{language(request.Locale)}}
	if err := p.getJSON(ctx, "/find/"+url.PathEscape(request.Value), query, &response); err != nil {
		return nil, err
	}
	raw := response.MovieResults
	if request.Kind == scraper.MediaKindSeries {
		raw = response.TVResults
	}
	result := make([]scraper.Candidate, 0, len(raw))
	for _, item := range raw {
		result = append(result, candidateFromSearch(request.Kind, item))
	}
	return result, nil
}

type detailsResponse struct {
	ID                int64             `json:"id"`
	Title             string            `json:"title"`
	Name              string            `json:"name"`
	OriginalTitle     string            `json:"original_title"`
	OriginalName      string            `json:"original_name"`
	Overview          string            `json:"overview"`
	Tagline           string            `json:"tagline"`
	ReleaseDate       string            `json:"release_date"`
	FirstAirDate      string            `json:"first_air_date"`
	LastAirDate       string            `json:"last_air_date"`
	Runtime           int               `json:"runtime"`
	EpisodeRunTime    []int             `json:"episode_run_time"`
	VoteAverage       float64           `json:"vote_average"`
	VoteCount         int               `json:"vote_count"`
	PosterPath        string            `json:"poster_path"`
	BackdropPath      string            `json:"backdrop_path"`
	Genres            []namedItem       `json:"genres"`
	Countries         []countryItem     `json:"production_countries"`
	Studios           []namedItem       `json:"production_companies"`
	Seasons           []seasonItem      `json:"seasons"`
	ExternalIDs       map[string]any    `json:"external_ids"`
	Credits           creditsResponse   `json:"credits"`
	AlternativeTitles alternativeTitles `json:"alternative_titles"`
	ReleaseDates      releaseDates      `json:"release_dates"`
	ContentRatings    contentRatings    `json:"content_ratings"`
}

type namedItem struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}
type countryItem struct {
	Code string `json:"iso_3166_1"`
	Name string `json:"name"`
}
type seasonItem struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	Overview     string `json:"overview"`
	AirDate      string `json:"air_date"`
	PosterPath   string `json:"poster_path"`
	SeasonNumber int    `json:"season_number"`
	EpisodeCount int    `json:"episode_count"`
}
type alternativeTitle struct {
	Title string `json:"title"`
}
type alternativeTitles struct {
	Titles  []alternativeTitle `json:"titles"`
	Results []alternativeTitle `json:"results"`
}
type castItem struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	Character   string `json:"character"`
	Order       int    `json:"order"`
	ProfilePath string `json:"profile_path"`
}
type crewItem struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	Department  string `json:"department"`
	Job         string `json:"job"`
	ProfilePath string `json:"profile_path"`
}
type creditsResponse struct {
	Cast []castItem `json:"cast"`
	Crew []crewItem `json:"crew"`
}
type releaseDates struct {
	Results []struct {
		Code  string `json:"iso_3166_1"`
		Dates []struct {
			Certification string `json:"certification"`
		} `json:"release_dates"`
	} `json:"results"`
}
type contentRatings struct {
	Results []struct {
		Code   string `json:"iso_3166_1"`
		Rating string `json:"rating"`
	} `json:"results"`
}

// FetchWork retrieves localized rich metadata for a known TMDb identity.
func (p *Provider) FetchWork(ctx context.Context, request scraper.WorkRequest) (scraper.WorkMetadata, error) {
	segment := "movie"
	appendValue := "alternative_titles,external_ids,credits,images,release_dates"
	if request.Kind == scraper.MediaKindSeries {
		segment = "tv"
		appendValue = "alternative_titles,external_ids,credits,images,content_ratings"
	}
	query := url.Values{
		"language":               []string{language(request.Locale)},
		"append_to_response":     []string{appendValue},
		"include_image_language": []string{imageLanguages(request.Locale)},
	}
	var response detailsResponse
	if err := p.getJSON(ctx, "/"+segment+"/"+url.PathEscape(request.ProviderItemID), query, &response); err != nil {
		return scraper.WorkMetadata{}, err
	}
	return p.normalizeWork(request.Kind, request.Locale, response), nil
}

type seasonResponse struct {
	ID           int64             `json:"id"`
	Name         string            `json:"name"`
	Overview     string            `json:"overview"`
	AirDate      string            `json:"air_date"`
	PosterPath   string            `json:"poster_path"`
	SeasonNumber int               `json:"season_number"`
	Episodes     []episodeResponse `json:"episodes"`
}
type episodeResponse struct {
	ID            int64   `json:"id"`
	Name          string  `json:"name"`
	Overview      string  `json:"overview"`
	AirDate       string  `json:"air_date"`
	Runtime       int     `json:"runtime"`
	VoteAverage   float64 `json:"vote_average"`
	StillPath     string  `json:"still_path"`
	SeasonNumber  int     `json:"season_number"`
	EpisodeNumber int     `json:"episode_number"`
}

// FetchSeason retrieves a season and its episode metadata.
func (p *Provider) FetchSeason(ctx context.Context, request scraper.SeasonRequest) (scraper.SeasonMetadata, error) {
	var response seasonResponse
	path := fmt.Sprintf("/tv/%s/season/%d", url.PathEscape(request.ProviderItemID), request.SeasonNumber)
	if err := p.getJSON(ctx, path, url.Values{"language": []string{language(request.Locale)}}, &response); err != nil {
		return scraper.SeasonMetadata{}, err
	}
	result := scraper.SeasonMetadata{
		ProviderSeasonID: strconv.FormatInt(response.ID, 10), SeasonNumber: response.SeasonNumber,
		Title: response.Name, Overview: response.Overview, AirDate: response.AirDate,
		Poster: artwork(response.PosterPath),
	}
	for _, episode := range response.Episodes {
		result.Episodes = append(result.Episodes, normalizeEpisode(episode))
	}
	return result, nil
}

// FetchEpisode retrieves one episode directly.
func (p *Provider) FetchEpisode(ctx context.Context, request scraper.EpisodeRequest) (scraper.EpisodeMetadata, error) {
	var response episodeResponse
	path := fmt.Sprintf("/tv/%s/season/%d/episode/%d", url.PathEscape(request.ProviderItemID), request.SeasonNumber, request.EpisodeNumber)
	if err := p.getJSON(ctx, path, url.Values{"language": []string{language(request.Locale)}}, &response); err != nil {
		return scraper.EpisodeMetadata{}, err
	}
	return normalizeEpisode(response), nil
}

// OpenArtwork streams one image referenced by a previous TMDb response.
func (p *Provider) OpenArtwork(ctx context.Context, request scraper.ArtworkRequest) (scraper.ArtworkContent, error) {
	if request.Reference.ProviderID != providerID || !strings.HasPrefix(request.Reference.Key, "/") ||
		strings.Contains(request.Reference.Key, "..") {
		return scraper.ArtworkContent{}, &scraper.ProviderError{
			ProviderID: providerID, Operation: "artwork", Kind: scraper.ErrorUnsupported,
		}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, p.options.ImageBaseURL+request.Reference.Key, nil)
	if err != nil {
		return scraper.ArtworkContent{}, err
	}
	response, err := p.client.Do(req)
	if err != nil {
		return scraper.ArtworkContent{}, providerError("artwork", scraper.ErrorTemporary, err, 0)
	}
	if response.StatusCode != http.StatusOK {
		defer response.Body.Close()
		return scraper.ArtworkContent{}, statusError("artwork", response)
	}
	mimeType, _, _ := mime.ParseMediaType(response.Header.Get("Content-Type"))
	return scraper.ArtworkContent{
		Body: response.Body, MIMEType: mimeType, ContentLength: response.ContentLength,
		ETag: response.Header.Get("ETag"),
	}, nil
}

// CheckHealth validates the configured token against TMDb configuration.
func (p *Provider) CheckHealth(ctx context.Context) scraper.HealthResult {
	var response map[string]any
	err := p.getJSON(ctx, "/configuration", nil, &response)
	message := ""
	if err != nil {
		message = "unavailable"
		var providerErr *scraper.ProviderError
		if errors.As(err, &providerErr) {
			message = string(providerErr.Kind)
		}
	}
	return scraper.HealthResult{Available: err == nil, Message: message, CheckedAt: time.Now().UTC()}
}

func (p *Provider) getJSON(ctx context.Context, path string, query url.Values, target any) error {
	endpoint := p.options.APIBaseURL + path
	if len(query) > 0 {
		endpoint += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+p.options.AccessToken)
	req.Header.Set("Accept", "application/json")
	response, err := p.client.Do(req)
	if err != nil {
		return providerError(path, scraper.ErrorTemporary, err, 0)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return statusError(path, response)
	}
	decoder := json.NewDecoder(io.LimitReader(response.Body, 8<<20))
	if err := decoder.Decode(target); err != nil {
		return providerError(path, scraper.ErrorInvalidResponse, err, 0)
	}
	return nil
}

func statusError(operation string, response *http.Response) error {
	kind := scraper.ErrorTemporary
	switch response.StatusCode {
	case http.StatusUnauthorized, http.StatusForbidden:
		kind = scraper.ErrorUnauthorized
	case http.StatusNotFound:
		kind = scraper.ErrorNotFound
	case http.StatusTooManyRequests:
		kind = scraper.ErrorRateLimited
	default:
		if response.StatusCode >= 400 && response.StatusCode < 500 {
			kind = scraper.ErrorInvalidResponse
		}
	}
	var retryAfter time.Duration
	if seconds, err := strconv.Atoi(response.Header.Get("Retry-After")); err == nil && seconds > 0 {
		retryAfter = time.Duration(seconds) * time.Second
	}
	return providerError(operation, kind, fmt.Errorf("HTTP %d", response.StatusCode), retryAfter)
}

func providerError(operation string, kind scraper.ErrorKind, err error, retryAfter time.Duration) error {
	return &scraper.ProviderError{
		ProviderID: providerID, Operation: operation, Kind: kind, Err: err, RetryAfter: retryAfter,
	}
}

func candidateFromSearch(kind scraper.MediaKind, item searchItem) scraper.Candidate {
	title, original, date := item.Title, item.OriginalTitle, item.ReleaseDate
	if kind == scraper.MediaKindSeries {
		title, original, date = item.Name, item.OriginalName, item.FirstAirDate
	}
	return scraper.Candidate{
		ProviderID: providerID, ProviderItemID: strconv.FormatInt(item.ID, 10), Kind: kind,
		Title: title, OriginalTitle: original, ReleaseDate: date, Overview: item.Overview,
		Popularity: item.Popularity, Poster: artwork(item.PosterPath), Backdrop: artwork(item.BackdropPath),
	}
}

func (p *Provider) normalizeWork(kind scraper.MediaKind, locale scraper.Locale, value detailsResponse) scraper.WorkMetadata {
	title, original, releaseDate := value.Title, value.OriginalTitle, value.ReleaseDate
	runtime := value.Runtime
	if kind == scraper.MediaKindSeries {
		title, original, releaseDate = value.Name, value.OriginalName, value.FirstAirDate
		if runtime == 0 && len(value.EpisodeRunTime) > 0 {
			runtime = value.EpisodeRunTime[0]
		}
	}
	result := scraper.WorkMetadata{
		ProviderID: providerID, ProviderItemID: strconv.FormatInt(value.ID, 10), Kind: kind,
		Title: title, OriginalTitle: original, Overview: value.Overview, Tagline: value.Tagline,
		ReleaseDate: releaseDate, EndDate: value.LastAirDate, VoteCount: value.VoteCount,
		ExternalIDs: stringMap(value.ExternalIDs), Poster: artwork(value.PosterPath), Backdrop: artwork(value.BackdropPath),
	}
	if value.VoteCount > 0 {
		rating := value.VoteAverage
		result.CommunityRating = &rating
	}
	if runtime > 0 {
		duration := time.Duration(runtime) * time.Minute
		result.Runtime = &duration
	}
	for _, item := range append(value.AlternativeTitles.Titles, value.AlternativeTitles.Results...) {
		if name := strings.TrimSpace(item.Title); name != "" {
			result.AlternativeTitles = append(result.AlternativeTitles, name)
		}
	}
	for _, item := range value.Genres {
		result.Genres = append(result.Genres, scraper.NamedValue{ID: strconv.FormatInt(item.ID, 10), Name: item.Name})
	}
	for _, item := range value.Countries {
		result.Countries = append(result.Countries, scraper.NamedValue{ID: item.Code, Name: item.Name})
	}
	for _, item := range value.Studios {
		result.Studios = append(result.Studios, scraper.NamedValue{ID: strconv.FormatInt(item.ID, 10), Name: item.Name})
	}
	for _, item := range value.Credits.Cast {
		result.Credits = append(result.Credits, scraper.Credit{
			ProviderPersonID: strconv.FormatInt(item.ID, 10), Name: item.Name, Character: item.Character,
			Order: item.Order, Profile: artwork(item.ProfilePath),
		})
	}
	for _, item := range value.Credits.Crew {
		result.Credits = append(result.Credits, scraper.Credit{
			ProviderPersonID: strconv.FormatInt(item.ID, 10), Name: item.Name, Department: item.Department,
			Job: item.Job, Profile: artwork(item.ProfilePath),
		})
	}
	for _, item := range value.Seasons {
		result.Seasons = append(result.Seasons, scraper.SeasonSummary{
			ProviderSeasonID: strconv.FormatInt(item.ID, 10), SeasonNumber: item.SeasonNumber,
			Title: item.Name, Overview: item.Overview, AirDate: item.AirDate,
			EpisodeCount: item.EpisodeCount, Poster: artwork(item.PosterPath),
		})
	}
	result.Certification = certification(kind, locale.Region, value)
	return result
}

func certification(kind scraper.MediaKind, region string, value detailsResponse) string {
	if kind == scraper.MediaKindSeries {
		for _, item := range value.ContentRatings.Results {
			if strings.EqualFold(item.Code, region) {
				return item.Rating
			}
		}
		return ""
	}
	for _, item := range value.ReleaseDates.Results {
		if !strings.EqualFold(item.Code, region) {
			continue
		}
		for _, release := range item.Dates {
			if release.Certification != "" {
				return release.Certification
			}
		}
	}
	return ""
}

func normalizeEpisode(value episodeResponse) scraper.EpisodeMetadata {
	result := scraper.EpisodeMetadata{
		ProviderEpisodeID: strconv.FormatInt(value.ID, 10), SeasonNumber: value.SeasonNumber,
		EpisodeNumber: value.EpisodeNumber, Title: value.Name, Overview: value.Overview,
		AirDate: value.AirDate, Still: artwork(value.StillPath),
	}
	if value.Runtime > 0 {
		duration := time.Duration(value.Runtime) * time.Minute
		result.Runtime = &duration
	}
	if value.VoteAverage > 0 {
		rating := value.VoteAverage
		result.CommunityRating = &rating
	}
	return result
}

func artwork(path string) *scraper.ArtworkRef {
	if path == "" {
		return nil
	}
	return &scraper.ArtworkRef{ProviderID: providerID, Key: path}
}

func language(locale scraper.Locale) string {
	if locale.Language == "" {
		return "zh-CN"
	}
	return locale.Language
}

func imageLanguages(locale scraper.Locale) string {
	values := []string{language(locale)}
	values = append(values, locale.FallbackLanguages...)
	values = append(values, "null")
	return strings.Join(values, ",")
}

func stringOption(raw map[string]any, key string) string {
	value, _ := raw[key].(string)
	return strings.TrimSpace(value)
}

func stringMap(raw map[string]any) map[string]string {
	result := map[string]string{}
	for key, value := range raw {
		if text, ok := value.(string); ok && strings.TrimSpace(text) != "" {
			result[strings.TrimSuffix(key, "_id")] = text
		}
	}
	return result
}
