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

const RuleVersion = 1

var (
	yearPattern    = regexp.MustCompile(`(?:^|[ ._\-\[(])(18\d{2}|19\d{2}|20\d{2}|21\d{2})(?:$|[ ._\-\])])`)
	episodePattern = regexp.MustCompile(`(?i)(?:^|[ ._\-])S(\d{1,2})E(\d{1,3})(?:$|[ ._\-])`)
	noisePattern   = regexp.MustCompile(`(?i)(?:^|[ ._\-])(2160p|1080p|720p|480p|4k|uhd|bluray|blu-ray|web-dl|webrip|hdtv|x26[45]|hevc|av1)(?:$|[ ._\-])`)
)

// Match derives a conservative movie or episode mapping from a source-scoped path.
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
		values := episodePattern.FindStringSubmatch(stem)
		if len(values) != 3 {
			match.Status = domain.CatalogMatchNeedsReview
			match.Confidence = 35
			break
		}
		season, _ := strconv.Atoi(values[1])
		episode, _ := strconv.Atoi(values[2])
		match.SeasonNumber = &season
		match.EpisodeNumber = &episode
		match.EpisodeTitle = episodeTitle(stem, values[0], season, episode)
		match.Confidence = 95
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

func episodeTitle(stem, token string, season, episode int) string {
	index := strings.Index(strings.ToLower(stem), strings.ToLower(strings.TrimSpace(token)))
	if index >= 0 {
		remaining := strings.Trim(stem[index+len(token):], " ._-")
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
