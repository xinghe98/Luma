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
	Provider       string
	ProviderItemID string
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
	ID                string
	SourceID          string
	Kind              string
	Title             string
	OriginalTitle     string
	Year              *int
	Overview          string
	Tagline           string
	ReleaseDate       string
	EndDate           string
	Certification     string
	CommunityRating   *float64
	VoteCount         int
	Genres            []CatalogNamedValue
	Countries         []CatalogNamedValue
	Studios           []CatalogNamedValue
	Credits           []CatalogCredit
	ExternalIDs       map[string]string
	MetadataStatus    string
	MetadataRevision  int
	MetadataErrorCode string
	Provider          string
	ProviderItemID    string
	IdentityLocked    bool
	PosterArtworkID   string
	BackdropArtworkID string
	MatchStatus       string
	MediaCount        int
	EpisodeCount      int
	CompletedCount    int
	PlayableMediaID   string
	ThumbnailMediaID  string
	// PosterMediaID 优先指向作品目录中的 poster/folder/cover 图片。
	PosterMediaID    string
	DurationMS       *int64
	Resolution       string
	ProgressMS       int64
	Completed        bool
	Favorite         bool
	FavoriteRevision int64
	UpdatedAt        time.Time
	Episodes         []CatalogEpisode
	Versions         []CatalogVersion
}

// CatalogNamedValue is a localized genre, country, or studio attached to a work.
type CatalogNamedValue struct {
	ID   string `json:"id,omitempty"`
	Name string `json:"name"`
}

// CatalogCredit is one normalized cast or crew contribution.
type CatalogCredit struct {
	ProviderPersonID string `json:"provider_person_id,omitempty"`
	Name             string `json:"name"`
	Character        string `json:"character,omitempty"`
	Department       string `json:"department,omitempty"`
	Job              string `json:"job,omitempty"`
	Order            int    `json:"order"`
	// ProfileArtworkID 仅供 API 层生成受鉴权头像地址，不会暴露 Provider 引用。
	ProfileArtworkID string `json:"-"`
}

// CatalogVersion 是同一作品可播放文件的真实技术信息。
type CatalogVersion struct {
	MediaID         string
	Label           string
	FileSize        int64
	DurationMS      *int64
	Resolution      string
	VideoCodec      string
	AudioCodec      string
	AudioTrackCount int
	ProgressMS      int64
	Completed       bool
	Selected        bool
}

// CatalogUserData 保存用户在一个作品上的跨版本状态。
type CatalogUserData struct {
	CatalogItemID string
	Favorite      bool
	Revision      int64
	UpdatedAt     time.Time
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
	CatalogItemID  string
	IssueType      string
	Reason         string
	Confidence     int
	CandidateCount int
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

// CatalogScrapeInput contains provider-neutral work hints claimed by a metadata worker.
type CatalogScrapeInput struct {
	ItemID   string
	SourceID string
	Kind     string
	Title    string
	// AlternativeTitles 是从同一作品的文件名和目录名中提取的版本或别名线索。
	AlternativeTitles []string
	Year              *int
	DurationMS        *int64
	Provider          string
	ProviderItemID    string
	IdentityLocked    bool
	MetadataRevision  int
}

// CatalogMetadataCandidate is a scored candidate persisted for manual identification.
type CatalogMetadataCandidate struct {
	ID             string
	ItemID         string
	Provider       string
	ProviderItemID string
	Title          string
	OriginalTitle  string
	Year           *int
	Overview       string
	Score          int
	Reasons        []string
	PosterRef      string
}

// CatalogMetadataResult is a normalized successful provider scrape.
type CatalogMetadataResult struct {
	ItemID            string
	Provider          string
	ProviderItemID    string
	Title             string
	OriginalTitle     string
	Year              *int
	AlternativeTitles []string
	Overview          string
	Tagline           string
	ReleaseDate       string
	EndDate           string
	RuntimeMS         *int64
	Certification     string
	CommunityRating   *float64
	VoteCount         int
	GenresJSON        string
	CountriesJSON     string
	StudiosJSON       string
	CreditsJSON       string
	ExternalIDsJSON   string
	PosterRef         string
	BackdropRef       string
}

// CatalogArtwork identifies a provider image visible to an authorized catalog user.
type CatalogArtwork struct {
	ID            string
	ItemID        string
	SourceID      string
	Provider      string
	OpaqueKey     string
	StorageKey    string
	MIMEType      string
	ContentSHA256 string
	Status        string
}

// CatalogSidecarContext lists linked media paths and indexed NFO paths for one work.
type CatalogSidecarContext struct {
	SourceID     string
	MediaPaths   []string
	SidecarPaths []string
}

// MetadataProviderStatus is a sanitized provider descriptor and health result.
type MetadataProviderStatus struct {
	ID           string
	Name         string
	Enabled      bool
	Capabilities []string
	Available    bool
	Message      string
}

// CatalogArtworkContent is an authenticated artwork response with cache validation metadata.
type CatalogArtworkContent struct {
	Data        []byte
	MIMEType    string
	ETag        string
	NotModified bool
}
