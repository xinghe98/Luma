package domain

import "time"

const (
	CatalogKindMovie  = "movie"
	CatalogKindSeries = "series"

	CatalogMatchMatched     = "matched"
	CatalogMatchNeedsReview = "needs_review"
	CatalogMatchIgnored     = "ignored"
)

// CatalogCandidate 是尚未按最新规则整理的文件索引。
type CatalogCandidate struct {
	MediaID        string
	SourceID       string
	LibraryKind    string
	RelativePath   string
	Filename       string
	MediaUpdatedAt time.Time
}

// CatalogMatch 是命名识别或用户修正生成的作品映射。
type CatalogMatch struct {
	MediaID        string
	SourceID       string
	Kind           string
	Title          string
	SortTitle      string
	Year           *int
	SeasonNumber   *int
	EpisodeNumber  *int
	EpisodeTitle   string
	Status         string
	Confidence     int
	Locked         bool
	Ignored        bool
	MediaUpdatedAt time.Time
}

// CatalogItem 是电影或剧集的作品级摘要。
type CatalogItem struct {
	ID               string
	SourceID         string
	Kind             string
	Title            string
	Year             *int
	MatchStatus      string
	MediaCount       int
	EpisodeCount     int
	CompletedCount   int
	PlayableMediaID  string
	ThumbnailMediaID string
	// PosterMediaID 优先指向作品目录中的 poster/folder/cover 图片。
	PosterMediaID string
	DurationMS    *int64
	Resolution    string
	ProgressMS    int64
	Completed     bool
	UpdatedAt     time.Time
	Episodes      []CatalogEpisode
}

// CatalogEpisode 是剧集详情中的一集及其实际播放文件。
type CatalogEpisode struct {
	ID               string
	SeasonNumber     int
	EpisodeNumber    int
	Title            string
	MediaID          string
	DurationMS       *int64
	Resolution       string
	ProgressMS       int64
	Completed        bool
	ThumbnailMediaID string
}

type CatalogListRequest struct {
	Kind  string
	Query string
	Limit int
}

type CatalogIssue struct {
	MediaID        string
	Filename       string
	SourceID       string
	LibraryKind    string
	SuggestedTitle string
	SeasonNumber   *int
	EpisodeNumber  *int
}

type UpdateCatalogMatchCommand struct {
	MediaID       string
	Kind          string
	Title         string
	Year          *int
	SeasonNumber  *int
	EpisodeNumber *int
	Ignored       bool
}
