// 本文件验证作品文件集合如何提供年份与版本别名，确保不确定线索不会触发自动匹配。
package catalog

import "testing"

func TestCollectScrapeEvidenceFromTVFiles(t *testing.T) {
	tests := []struct {
		name      string
		title     string
		paths     []string
		wantYear  int
		wantAlias string
	}{
		{
			name:  "三体年份",
			title: "三体",
			paths: []string{
				"三体/three.body.2023.ep01.hd1080p.mkv",
				"三体/three.body.2023.ep02.hd1080p.mkv",
			},
			wantYear: 2023,
		},
		{
			name:  "非自然死亡年份",
			title: "非自然死亡",
			paths: []string{
				"非自然死亡/非自然死亡.第1集.unnatural.2018.e01.mkv",
				"非自然死亡/非自然死亡.第2集.unnatural.2018.e02.mkv",
			},
			wantYear: 2018,
		},
		{
			name:  "网剧版别名",
			title: "画江湖之不良人",
			paths: []string{
				"画江湖之不良人/画江湖之不良人网剧版01.mp4",
				"画江湖之不良人/画江湖之不良人网剧版02.mp4",
			},
			wantAlias: "画江湖之不良人网剧版",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			evidence := CollectScrapeEvidence(test.title, test.paths)
			if test.wantYear == 0 {
				if evidence.Year != nil {
					t.Fatalf("年份=%d，期望没有年份", *evidence.Year)
				}
			} else if evidence.Year == nil || *evidence.Year != test.wantYear {
				t.Fatalf("年份=%v，期望=%d", evidence.Year, test.wantYear)
			}
			if test.wantAlias != "" && !contains(evidence.AlternativeTitles, test.wantAlias) {
				t.Fatalf("别名=%#v，缺少=%q", evidence.AlternativeTitles, test.wantAlias)
			}
		})
	}
}

func TestCollectScrapeEvidenceLeavesConflictingYearsUnset(t *testing.T) {
	evidence := CollectScrapeEvidence("同名剧", []string{
		"同名剧/同名剧.2018.E01.mkv",
		"同名剧/同名剧.2019.E02.mkv",
	})
	if evidence.Year != nil {
		t.Fatalf("冲突年份=%d，不应自动采用", *evidence.Year)
	}
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
