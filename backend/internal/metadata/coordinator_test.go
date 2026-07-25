// 本文件验证影视候选评分在常见无年份目录下仍能自动确认准确标题。
package metadata

import (
	"context"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

func TestScoreCandidateExactTitleWithoutYearMeetsAutoMatchThreshold(t *testing.T) {
	score, reasons := scoreCandidate(
		domain.CatalogScrapeInput{Title: "三体"},
		scraper.Candidate{Title: "三体", ReleaseDate: "2023-01-15"},
	)
	if score < 90 {
		t.Fatalf("无年份的完整标题得分 = %d，不能达到自动确认阈值；原因=%#v", score, reasons)
	}
}

func TestScoreCandidatePartialTitleWithoutYearRemainsConservative(t *testing.T) {
	score, _ := scoreCandidate(
		domain.CatalogScrapeInput{Title: "三体电视剧"},
		scraper.Candidate{Title: "三体", ReleaseDate: "2023-01-15"},
	)
	if score >= 90 {
		t.Fatalf("部分标题在缺少年份时不应自动确认，得分 = %d", score)
	}
}

func TestScoreCandidatePrefersExactFileVariantAlias(t *testing.T) {
	input := domain.CatalogScrapeInput{
		Title: "画江湖之不良人", AlternativeTitles: []string{"画江湖之不良人网剧版"},
	}
	matched, reasons := scoreCandidate(input, scraper.Candidate{
		Title: "画江湖之不良人", AlternativeTitles: []string{"画江湖之不良人网剧版"},
	})
	plain, _ := scoreCandidate(input, scraper.Candidate{Title: "画江湖之不良人"})
	if matched-plain < 8 || !containsReason(reasons, "文件版本别名匹配") {
		t.Fatalf("版本别名未拉开足够分差：matched=%d plain=%d reasons=%#v", matched, plain, reasons)
	}
}

func TestSearchQueriesDeduplicatesAndLimitsVariantHints(t *testing.T) {
	queries := searchQueries(domain.CatalogScrapeInput{
		Title: "画江湖之不良人", AlternativeTitles: []string{
			"画江湖之不良人", "画江湖之不良人网剧版", "不良人电视剧", "Bu Liang Ren", "不应请求",
		},
	})
	if len(queries) != 4 || queries[0] != "画江湖之不良人" || queries[1] != "画江湖之不良人网剧版" {
		t.Fatalf("查询=%#v", queries)
	}
}

func TestResolveLoadsSameNameCandidateAliasesBeforeSelecting(t *testing.T) {
	provider := &variantTestProvider{}
	registry := NewRegistry()
	if err := registry.Register(provider); err != nil {
		t.Fatal(err)
	}
	coordinator, err := NewCoordinator(registry, scraper.Locale{Language: "zh-CN"}, 90, 8)
	if err != nil {
		t.Fatal(err)
	}
	outcome, err := coordinator.Resolve(context.Background(), domain.CatalogScrapeInput{
		ItemID: "catalog", Kind: domain.CatalogKindSeries, Title: "画江湖之不良人",
		AlternativeTitles: []string{"画江湖之不良人网剧版"},
	})
	if err != nil || outcome.Result == nil || outcome.Result.ProviderItemID != "web" {
		t.Fatalf("outcome=%#v error=%v", outcome, err)
	}
}

func TestResolveAutoSelectsDeterministicTopCandidateWhenMarginIsZero(t *testing.T) {
	provider := &variantTestProvider{}
	registry := NewRegistry()
	if err := registry.Register(provider); err != nil {
		t.Fatal(err)
	}
	coordinator, err := NewCoordinator(registry, scraper.Locale{Language: "zh-CN"}, 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	outcome, err := coordinator.Resolve(context.Background(), domain.CatalogScrapeInput{
		ItemID: "catalog", Kind: domain.CatalogKindSeries, Title: "画江湖之不良人",
	})
	if err != nil || outcome.Result == nil || outcome.Result.ProviderItemID != "plain" {
		t.Fatalf("outcome=%#v error=%v", outcome, err)
	}
}

type variantTestProvider struct{}

func (*variantTestProvider) Descriptor() scraper.Descriptor {
	return scraper.Descriptor{
		ID: "test", Name: "测试", Kinds: []scraper.MediaKind{scraper.MediaKindSeries},
		Capabilities: []scraper.Capability{scraper.CapabilitySearch, scraper.CapabilityWork},
	}
}

func (*variantTestProvider) Search(_ context.Context, _ scraper.SearchRequest) (scraper.SearchPage, error) {
	return scraper.SearchPage{Items: []scraper.Candidate{
		{ProviderID: "test", ProviderItemID: "plain", Kind: scraper.MediaKindSeries, Title: "画江湖之不良人"},
		{ProviderID: "test", ProviderItemID: "web", Kind: scraper.MediaKindSeries, Title: "画江湖之不良人"},
	}}, nil
}

func (*variantTestProvider) FetchWork(_ context.Context, request scraper.WorkRequest) (scraper.WorkMetadata, error) {
	work := scraper.WorkMetadata{
		ProviderID: "test", ProviderItemID: request.ProviderItemID, Kind: scraper.MediaKindSeries,
		Title: "画江湖之不良人",
	}
	if request.ProviderItemID == "web" {
		work.AlternativeTitles = []string{"画江湖之不良人网剧版"}
	}
	return work, nil
}

func containsReason(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
