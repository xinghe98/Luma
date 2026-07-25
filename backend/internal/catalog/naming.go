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

const RuleVersion = 3

var (
	yearPattern                 = regexp.MustCompile(`(?:^|[ ._\-\[(])(18\d{2}|19\d{2}|20\d{2}|21\d{2})(?:$|[ ._\-\])])`)
	seasonEpisodePattern        = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])S(\d{1,2})E(\d{1,3})(?:$|[ ._\-\])])`)
	chineseEpisodePattern       = regexp.MustCompile(`第[ ._\-]*(\d{1,3})[ ._\-]*集`)
	episodeOnlyPattern          = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])EP?(\d{1,3})(?:$|[ ._\-\])])`)
	seasonDirectoryPattern      = regexp.MustCompile(`(?i)^(?:season|s)[ ._\-]*(\d{1,2})$`)
	chineseSeasonPattern        = regexp.MustCompile(`^第[ ._\-]*(\d{1,2})[ ._\-]*季$`)
	trailingDigitsPattern       = regexp.MustCompile(`([0-9]{1,3})$`)
	noisePattern                = regexp.MustCompile(`(?i)(?:^|[ ._\-])(2160p|1080p|720p|480p|4k|uhd|bluray|blu-ray|web-dl|webrip|hdtv|x26[45]|hevc|av1)(?:$|[ ._\-])`)
	releaseMetadataPattern      = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])(18\d{2}|19\d{2}|20\d{2}|21\d{2}|4320p|2160p|hd1080p|1080p|720p|480p|4k|8k|uhd|hdr|dv|bluray|blu-ray|bd|web|web-dl|webrip|hdtv|remux|x26[45]|h26[45]|hevc|av1|aac|dts|ac3|mandarin|cantonese|chs|cht|eng|bdys|99mp4)(?:$|[ ._\-\])])`)
	providerIDPattern           = regexp.MustCompile(`(?i)\[(tmdbid)-([0-9]+)\]`)
	websitePrefixPattern        = regexp.MustCompile(`(?i)^(?:电影天堂)?[ ._-]*www[ ._-]*[a-z0-9]+[ ._-]*(?:com|cn|net)[ ._-]*`)
	movieReleasePattern         = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])(hd1080p|4320p|2160p|1080p|720p|480p|4k|8k|uhd|hdr|dv|bluray|blu-ray|bdrip|bd|web-dl|webrip|hdtv|remux|x26[45]|h26[45]|hevc|10bit|2audio|dts(?:-hd)?|aac|ac3|momo(?:hd)?|人人影视|国语中字|日语中字|中英字幕|中英双字|中文字幕|中字|双字|hk)(?:$|[ ._\-\])])`)
	compactReleaseSuffixPattern = regexp.MustCompile(`(?i)(?:BD|HD|BDrip)?(?:国语|粤语|日语|英语|中英)?(?:中字|字幕|双字)+$`)
)

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
		match.Title, match.Year, match.Provider, match.ProviderItemID, match.Confidence = matchMovie(stem, parts)
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

func matchMovie(stem string, parts []string) (title string, year *int, provider, providerItemID string, confidence int) {
	fileTitle, fileYear := cleanMovieTitle(stem)
	title, year, confidence = fileTitle, fileYear, 75
	if len(parts) > 1 {
		parent := strings.TrimSpace(parts[len(parts)-2])
		// Release folders copied from a filename frequently retain a video extension.
		if extension := filepath.Ext(parent); isVideoExtension(extension) {
			parent = strings.TrimSuffix(parent, extension)
		}
		parentTitle, parentYear := cleanMovieTitle(parent)
		if parentTitle != "" {
			title, confidence = parentTitle, 85
			if parentYear != nil {
				year = parentYear
			} else if fileYear != nil {
				year = fileYear
			}
			parentKey, fileKey := NormalizeTitle(parentTitle), NormalizeTitle(fileTitle)
			if fileKey != "" && parentKey != "" &&
				(strings.Contains(parentKey, fileKey) || strings.Contains(fileKey, parentKey)) {
				confidence = 90
				if len([]rune(fileTitle)) < len([]rune(parentTitle)) {
					title = fileTitle
				}
			}
		}
	}
	for _, value := range append([]string{stem}, parts...) {
		if found := providerIDPattern.FindStringSubmatch(value); len(found) == 3 {
			provider, providerItemID, confidence = "tmdb", found[2], 100
			break
		}
	}
	return title, year, provider, providerItemID, confidence
}

func cleanMovieTitle(value string) (string, *int) {
	value = providerIDPattern.ReplaceAllString(value, " ")
	value = strings.NewReplacer("[", " ", "]", " ", "(", " (", ")", ") ").Replace(value)
	value = websitePrefixPattern.ReplaceAllString(strings.TrimSpace(value), "")
	title, year := cleanTitle(value)
	if location := movieReleasePattern.FindStringIndex(title); location != nil {
		title = title[:location[0]]
	}
	title = compactReleaseSuffixPattern.ReplaceAllString(strings.TrimSpace(title), "")
	title = strings.Trim(title, " ._-[]()")
	return strings.Join(strings.Fields(title), " "), year
}

func isVideoExtension(extension string) bool {
	switch strings.ToLower(extension) {
	case ".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v", ".ts":
		return true
	default:
		return false
	}
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

func NormalizeTitle(value string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return unicode.ToLower(r)
		}
		return -1
	}, value)
}

func StableID(prefix string, values ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(values, "\x00")))
	return prefix + "_" + hex.EncodeToString(sum[:12])
}
