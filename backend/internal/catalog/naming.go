// Package catalog contains deterministic, offline-first media naming rules.
package catalog

import (
	"crypto/sha256"
	"encoding/hex"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

const RuleVersion = 2

var (
	yearPattern            = regexp.MustCompile(`(?:^|[ ._\-\[(])(18\d{2}|19\d{2}|20\d{2}|21\d{2})(?:$|[ ._\-\])])`)
	seasonEpisodePattern   = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])S(\d{1,2})E(\d{1,3})(?:$|[ ._\-\])])`)
	chineseEpisodePattern  = regexp.MustCompile(`第[ ._\-]*(\d{1,3})[ ._\-]*集`)
	episodeOnlyPattern     = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])EP?(\d{1,3})(?:$|[ ._\-\])])`)
	seasonDirectoryPattern = regexp.MustCompile(`(?i)^(?:season|s)[ ._\-]*(\d{1,2})$`)
	chineseSeasonPattern   = regexp.MustCompile(`^第[ ._\-]*(\d{1,2})[ ._\-]*季$`)
	trailingDigitsPattern  = regexp.MustCompile(`([0-9]{1,3})$`)
	noisePattern           = regexp.MustCompile(`(?i)(?:^|[ ._\-])(2160p|1080p|720p|480p|4k|uhd|bluray|blu-ray|web-dl|webrip|hdtv|x26[45]|hevc|av1)(?:$|[ ._\-])`)
	releaseMetadataPattern = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])(18\d{2}|19\d{2}|20\d{2}|21\d{2}|4320p|2160p|hd1080p|1080p|720p|480p|4k|8k|uhd|hdr|dv|bluray|blu-ray|bd|web|web-dl|webrip|hdtv|remux|x26[45]|h26[45]|hevc|av1|aac|dts|ac3|mandarin|cantonese|chs|cht|eng|bdys|99mp4)(?:$|[ ._\-\])])`)
)

// Match derives a conservative movie or episode mapping from a source-scoped
// path. TV matches accept common episode-only names, but ambiguous or
// conflicting numbering remains queued for manual review.
func Match(candidate domain.CatalogCandidate) domain.CatalogMatch {
	match := domain.CatalogMatch{
		MediaID: candidate.MediaID, SourceID: candidate.SourceID,
		Status: domain.CatalogMatchMatched, Confidence: 85,
		MediaUpdatedAt: candidate.MediaUpdatedAt,
	}
	cleanPath := filepath.ToSlash(candidate.RelativePath)
	parts := strings.Split(strings.Trim(cleanPath, "/"), "/")
	stem := strings.TrimSuffix(candidate.Filename, filepath.Ext(candidate.Filename))
	switch candidate.LibraryKind {
	case domain.LibraryKindMovies:
		match.Kind = domain.CatalogKindMovie
		name := stem
		if len(parts) > 1 {
			name = parts[len(parts)-2]
			match.Confidence = 95
		}
		match.Title, match.Year = cleanTitle(name)
	case domain.LibraryKindTV:
		match.Kind = domain.CatalogKindSeries
		showName := stem
		if len(parts) > 1 {
			showName = parts[0]
		}
		match.Title, match.Year = cleanTitle(showName)
		season, episode, tokenEnd, confidence, ok, conflict := matchTVEpisode(stem, showName, parts)
		if conflict {
			match.Status = domain.CatalogMatchNeedsReview
			match.Confidence = 20
			break
		}
		if !ok {
			match.Status = domain.CatalogMatchNeedsReview
			match.Confidence = 35
			break
		}
		match.SeasonNumber = &season
		match.EpisodeNumber = &episode
		match.EpisodeTitle = episodeTitle(stem, tokenEnd, episode)
		match.Confidence = confidence
	default:
		match.Status = domain.CatalogMatchIgnored
		match.Ignored = true
	}
	if match.Title == "" {
		match.Title = stem
		match.Status = domain.CatalogMatchNeedsReview
		match.Confidence = 20
	}
	match.SortTitle = NormalizeTitle(match.Title)
	return match
}

func cleanTitle(value string) (string, *int) {
	value = strings.TrimSpace(value)
	var year *int
	if found := yearPattern.FindStringSubmatch(value); len(found) == 2 {
		parsed, _ := strconv.Atoi(found[1])
		year = &parsed
		value = strings.Replace(value, found[0], " ", 1)
	}
	if location := noisePattern.FindStringIndex(value); location != nil {
		value = value[:location[0]]
	}
	value = strings.NewReplacer(".", " ", "_", " ", "[", " ", "]", " ").Replace(value)
	return strings.Join(strings.Fields(value), " "), year
}

type episodeSignal struct {
	season     *int
	episode    int
	tokenEnd   int
	confidence int
}

// matchTVEpisode reconciles explicit filename signals with an optional season
// directory. Missing seasons default to one; conflicting signals never guess.
func matchTVEpisode(stem, showName string, parts []string) (season, episode, tokenEnd, confidence int, ok, conflict bool) {
	directorySeason, hasDirectorySeason := seasonFromParents(parts)
	signals := explicitEpisodeSignals(stem)
	if len(signals) == 0 {
		episode, tokenEnd, ok = bareEpisodeNumber(stem, showName)
		if !ok {
			return 0, 0, 0, 0, false, false
		}
		if hasDirectorySeason {
			season = directorySeason
		} else {
			season = 1
		}
		return season, episode, tokenEnd, 75, true, false
	}

	episode = signals[0].episode
	seasonSet := hasDirectorySeason
	if hasDirectorySeason {
		season = directorySeason
	}
	best := signals[0]
	for _, signal := range signals {
		if signal.episode != episode {
			return 0, 0, 0, 0, false, true
		}
		if signal.season != nil {
			if seasonSet && season != *signal.season {
				return 0, 0, 0, 0, false, true
			}
			season = *signal.season
			seasonSet = true
		}
		if signal.confidence > best.confidence ||
			(signal.confidence == best.confidence && signal.tokenEnd > best.tokenEnd) {
			best = signal
		}
	}
	if !seasonSet {
		season = 1
	}
	return season, episode, best.tokenEnd, best.confidence, true, false
}

func explicitEpisodeSignals(stem string) []episodeSignal {
	signals := make([]episodeSignal, 0, 3)
	for _, indexes := range seasonEpisodePattern.FindAllStringSubmatchIndex(stem, -1) {
		season, _ := strconv.Atoi(stem[indexes[2]:indexes[3]])
		episode, _ := strconv.Atoi(stem[indexes[4]:indexes[5]])
		if episode <= 0 {
			continue
		}
		signals = append(signals, episodeSignal{
			season: &season, episode: episode, tokenEnd: indexes[1], confidence: 95,
		})
	}
	for _, indexes := range chineseEpisodePattern.FindAllStringSubmatchIndex(stem, -1) {
		episode, _ := strconv.Atoi(stem[indexes[2]:indexes[3]])
		if episode > 0 {
			signals = append(signals, episodeSignal{
				episode: episode, tokenEnd: indexes[1], confidence: 90,
			})
		}
	}
	for _, indexes := range episodeOnlyPattern.FindAllStringSubmatchIndex(stem, -1) {
		episode, _ := strconv.Atoi(stem[indexes[2]:indexes[3]])
		if episode > 0 {
			signals = append(signals, episodeSignal{
				episode: episode, tokenEnd: indexes[1], confidence: 90,
			})
		}
	}
	return signals
}

func seasonFromParents(parts []string) (int, bool) {
	for index := len(parts) - 2; index > 0; index-- {
		name := strings.TrimSpace(parts[index])
		switch strings.ToLower(name) {
		case "special", "specials":
			return 0, true
		case "特别篇":
			return 0, true
		}
		for _, pattern := range []*regexp.Regexp{seasonDirectoryPattern, chineseSeasonPattern} {
			values := pattern.FindStringSubmatch(name)
			if len(values) == 2 {
				season, _ := strconv.Atoi(values[1])
				return season, true
			}
		}
	}
	return 0, false
}

// bareEpisodeNumber handles only an episode-like numeric stem or a show-title
// prefix followed by one to three digits. Four-digit years and resolutions are
// therefore never accepted by this fallback.
func bareEpisodeNumber(stem, showName string) (episode, tokenEnd int, ok bool) {
	cleaned := stem
	if location := releaseMetadataPattern.FindStringIndex(cleaned); location != nil {
		cleaned = cleaned[:location[0]]
	}
	cleaned = strings.Trim(cleaned, " ._-[]()")
	if value, valid := positiveEpisodeNumber(cleaned); valid {
		return value, len(stem), true
	}

	normalized := NormalizeTitle(cleaned)
	showKey := NormalizeTitle(showName)
	if showKey == "" || !strings.HasPrefix(normalized, showKey) {
		return 0, 0, false
	}
	remainder := strings.TrimPrefix(normalized, showKey)
	indexes := trailingDigitsPattern.FindStringSubmatchIndex(remainder)
	if indexes == nil || indexes[1] != len(remainder) {
		return 0, 0, false
	}
	qualifier := remainder[:indexes[2]]
	if strings.IndexFunc(qualifier, unicode.IsDigit) >= 0 {
		return 0, 0, false
	}
	value, valid := positiveEpisodeNumber(remainder[indexes[2]:indexes[3]])
	if !valid {
		return 0, 0, false
	}
	return value, len(stem), true
}

func positiveEpisodeNumber(value string) (int, bool) {
	if len(value) < 1 || len(value) > 3 {
		return 0, false
	}
	number, err := strconv.Atoi(value)
	return number, err == nil && number > 0
}

func episodeTitle(stem string, tokenEnd, episode int) string {
	if tokenEnd >= 0 && tokenEnd <= len(stem) {
		remaining := stem[tokenEnd:]
		if location := releaseMetadataPattern.FindStringIndex(remaining); location != nil {
			remaining = remaining[:location[0]]
		}
		remaining = strings.Trim(remaining, " ._-[]()")
		remaining = strings.Join(strings.Fields(strings.NewReplacer(".", " ", "_", " ").Replace(remaining)), " ")
		if remaining != "" && noisePattern.FindStringIndex(remaining) == nil {
			return remaining
		}
	}
	return "第 " + strconv.Itoa(episode) + " 集"
}

// NormalizeTitle produces the stable, case-insensitive catalog identity key.
func NormalizeTitle(value string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return unicode.ToLower(r)
		}
		return -1
	}, value)
}

// StableID creates a short deterministic identifier without exposing paths.
func StableID(prefix string, values ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(values, "\x00")))
	return prefix + "_" + hex.EncodeToString(sum[:12])
}
