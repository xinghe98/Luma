// 本文件从同一作品的已匹配文件中汇总刮削线索，供元数据任务使用，不能据此直接修改作品身份。
package catalog

import (
	"path/filepath"
	"sort"
	"strings"
)

// ScrapeEvidence 是文件集合中可安全用于在线刮削的补充线索。
type ScrapeEvidence struct {
	Year              *int
	AlternativeTitles []string
}

// CollectScrapeEvidence 汇总文件路径中有多数共识的年份与以作品名开头的版本别名。
// 年份冲突或证据不足时不会给出年份，避免用单个发布标签误选同名作品。
func CollectScrapeEvidence(title string, relativePaths []string) ScrapeEvidence {
	yearCounts := map[int]int{}
	aliases := map[string]string{}
	yearSamples := 0
	canonical := NormalizeTitle(title)
	for _, relativePath := range relativePaths {
		parts := strings.Split(filepath.ToSlash(relativePath), "/")
		fileYears := map[int]struct{}{}
		for _, part := range parts {
			for _, match := range yearPattern.FindAllStringSubmatch(part, -1) {
				if len(match) != 2 {
					continue
				}
				year := parseYear(match[1])
				if year != 0 {
					fileYears[year] = struct{}{}
				}
			}
			if alias := variantAlias(canonical, part); alias != "" {
				aliases[NormalizeTitle(alias)] = alias
			}
		}
		if len(fileYears) > 0 {
			yearSamples++
			for year := range fileYears {
				yearCounts[year]++
			}
		}
	}

	evidence := ScrapeEvidence{Year: consensusYear(yearCounts, yearSamples)}
	keys := make([]string, 0, len(aliases))
	for key := range aliases {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		evidence.AlternativeTitles = append(evidence.AlternativeTitles, aliases[key])
	}
	return evidence
}

func parseYear(value string) int {
	if len(value) != 4 {
		return 0
	}
	year := 0
	for _, digit := range value {
		year = year*10 + int(digit-'0')
	}
	return year
}

func consensusYear(counts map[int]int, samples int) *int {
	if samples < 2 {
		return nil
	}
	bestYear, bestCount, secondCount := 0, 0, 0
	for year, count := range counts {
		if count > bestCount {
			secondCount, bestYear, bestCount = bestCount, year, count
		} else if count > secondCount {
			secondCount = count
		}
	}
	if bestCount < 2 || bestCount*100 < samples*80 || bestCount == secondCount {
		return nil
	}
	return &bestYear
}

func variantAlias(canonical, value string) string {
	if canonical == "" {
		return ""
	}
	value = strings.TrimSuffix(value, filepath.Ext(value))
	value = seasonEpisodePattern.ReplaceAllString(value, " ")
	value = chineseEpisodePattern.ReplaceAllString(value, " ")
	value = episodeOnlyPattern.ReplaceAllString(value, " ")
	value = trailingDigitsPattern.ReplaceAllString(value, "")
	if location := releaseMetadataPattern.FindStringIndex(value); location != nil {
		value = value[:location[0]]
	}
	value = strings.Join(strings.Fields(strings.NewReplacer(".", " ", "_", " ", "[", " ", "]", " ").Replace(value)), " ")
	normalized := NormalizeTitle(value)
	if normalized == canonical || !strings.HasPrefix(normalized, canonical) {
		return ""
	}
	return value
}
