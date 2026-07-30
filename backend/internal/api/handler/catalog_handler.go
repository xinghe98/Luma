package handler

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	apirequest "github.com/xinghe98/Luma/backend/internal/api/request"
	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

type CatalogUseCase interface {
	List(context.Context, domain.CatalogListRequest, string) ([]domain.CatalogItem, error)
	Get(context.Context, string, string) (domain.CatalogItem, error)
}

type catalogMetadataUseCase interface {
	MetadataCandidates(context.Context, string) ([]domain.CatalogMetadataCandidate, error)
	RefreshMetadata(context.Context, string, string) (int, error)
	SelectMetadataIdentity(context.Context, string, string, string, int) error
	MetadataProviders(context.Context) []domain.MetadataProviderStatus
	Artwork(context.Context, string, string, string) (domain.CatalogArtworkContent, error)
}

type catalogFavoriteUseCase interface {
	UpdateFavorite(context.Context, string, string, bool, int64) (domain.CatalogUserData, error)
}

type CatalogHandler struct{ service CatalogUseCase }

func NewCatalogHandler(service CatalogUseCase) (*CatalogHandler, error) {
	if service == nil {
		return nil, errors.New("作品库业务用例不能为空")
	}
	return &CatalogHandler{service: service}, nil
}

type catalogEpisodeJSON struct {
	ID            string `json:"id"`
	SeasonNumber  int    `json:"season_number"`
	EpisodeNumber int    `json:"episode_number"`
	Title         string `json:"title"`
	MediaID       string `json:"media_id"`
	DurationMS    *int64 `json:"duration_ms"`
	Resolution    string `json:"resolution"`
	ProgressMS    int64  `json:"progress_ms"`
	Completed     bool   `json:"completed"`
	ThumbnailURL  string `json:"thumbnail_url"`
}

type catalogItemJSON struct {
	ID                string                     `json:"id"`
	SourceID          string                     `json:"source_id"`
	Kind              string                     `json:"kind"`
	Title             string                     `json:"title"`
	OriginalTitle     string                     `json:"original_title"`
	Year              *int                       `json:"year"`
	Overview          string                     `json:"overview,omitempty"`
	Tagline           string                     `json:"tagline,omitempty"`
	ReleaseDate       string                     `json:"release_date"`
	EndDate           string                     `json:"end_date"`
	Certification     string                     `json:"certification"`
	CommunityRating   *float64                   `json:"community_rating"`
	VoteCount         int                        `json:"vote_count"`
	Genres            []domain.CatalogNamedValue `json:"genres"`
	Countries         []domain.CatalogNamedValue `json:"countries,omitempty"`
	Studios           []domain.CatalogNamedValue `json:"studios,omitempty"`
	Credits           []catalogCreditJSON        `json:"credits,omitempty"`
	ExternalIDs       map[string]string          `json:"external_ids,omitempty"`
	MatchStatus       string                     `json:"match_status"`
	MetadataStatus    string                     `json:"metadata_status"`
	MetadataRevision  int                        `json:"metadata_revision"`
	MetadataErrorCode string                     `json:"metadata_error_code"`
	Provider          string                     `json:"provider"`
	ProviderItemID    string                     `json:"provider_item_id"`
	IdentityLocked    bool                       `json:"identity_locked"`
	MediaCount        int                        `json:"media_count"`
	EpisodeCount      int                        `json:"episode_count"`
	CompletedCount    int                        `json:"completed_count"`
	PlayableMediaID   string                     `json:"playable_media_id"`
	ThumbnailURL      string                     `json:"thumbnail_url"`
	PosterURL         string                     `json:"poster_url"`
	BackdropURL       string                     `json:"backdrop_url"`
	DurationMS        *int64                     `json:"duration_ms"`
	Resolution        string                     `json:"resolution"`
	ProgressMS        int64                      `json:"progress_ms"`
	Completed         bool                       `json:"completed"`
	Favorite          bool                       `json:"favorite"`
	FavoriteRevision  int64                      `json:"favorite_revision"`
	UpdatedAt         string                     `json:"updated_at"`
	Episodes          []catalogEpisodeJSON       `json:"episodes,omitempty"`
	Versions          []catalogVersionJSON       `json:"versions,omitempty"`
}

type catalogCreditJSON struct {
	ProviderPersonID string `json:"provider_person_id,omitempty"`
	Name             string `json:"name"`
	Character        string `json:"character,omitempty"`
	Department       string `json:"department,omitempty"`
	Job              string `json:"job,omitempty"`
	Order            int    `json:"order"`
	ProfileURL       string `json:"profile_url,omitempty"`
}

type catalogVersionJSON struct {
	MediaID         string `json:"media_id"`
	Label           string `json:"label"`
	FileSize        int64  `json:"file_size"`
	DurationMS      *int64 `json:"duration_ms"`
	Resolution      string `json:"resolution"`
	VideoCodec      string `json:"video_codec"`
	AudioCodec      string `json:"audio_codec"`
	AudioTrackCount int    `json:"audio_track_count"`
	ProgressMS      int64  `json:"progress_ms"`
	Completed       bool   `json:"completed"`
	Selected        bool   `json:"selected"`
}

func (h *CatalogHandler) List(c *gin.Context) {
	limit, ok := parseOptionalLimit(c)
	if !ok {
		return
	}
	items, err := h.service.List(c.Request.Context(), domain.CatalogListRequest{Kind: c.Query("kind"), Query: c.Query("q"), Limit: limit}, c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	result := make([]catalogItemJSON, 0, len(items))
	for _, item := range items {
		result = append(result, presentCatalog(item, false))
	}
	c.JSON(http.StatusOK, gin.H{"items": result})
}

func (h *CatalogHandler) Get(c *gin.Context) {
	item, err := h.service.Get(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentCatalog(item, true))
}

func presentCatalog(item domain.CatalogItem, includeEpisodes bool) catalogItemJSON {
	result := catalogItemJSON{ID: item.ID, SourceID: item.SourceID, Kind: item.Kind, Title: item.Title,
		OriginalTitle: item.OriginalTitle, Year: item.Year, Overview: item.Overview, Tagline: item.Tagline,
		ReleaseDate: item.ReleaseDate, EndDate: item.EndDate, Certification: item.Certification,
		CommunityRating: item.CommunityRating, VoteCount: item.VoteCount, Genres: nonNilNamed(item.Genres),
		Countries: item.Countries, Studios: item.Studios, Credits: presentCredits(item.Credits), ExternalIDs: item.ExternalIDs,
		MatchStatus: item.MatchStatus, MetadataStatus: item.MetadataStatus,
		MetadataRevision: item.MetadataRevision, MetadataErrorCode: item.MetadataErrorCode,
		Provider: item.Provider, ProviderItemID: item.ProviderItemID, IdentityLocked: item.IdentityLocked,
		MediaCount: item.MediaCount, EpisodeCount: item.EpisodeCount, CompletedCount: item.CompletedCount,
		PlayableMediaID: item.PlayableMediaID, DurationMS: item.DurationMS, Resolution: item.Resolution, ProgressMS: item.ProgressMS, Completed: item.Completed,
		Favorite: item.Favorite, FavoriteRevision: item.FavoriteRevision,
		UpdatedAt: item.UpdatedAt.UTC().Format(time.RFC3339Nano)}
	if item.ThumbnailMediaID != "" {
		result.ThumbnailURL = "/api/v1/media/" + url.PathEscape(item.ThumbnailMediaID) + "/thumbnail"
	}
	if item.PosterArtworkID != "" {
		result.PosterURL = "/api/v1/catalog/artwork/" + url.PathEscape(item.PosterArtworkID)
	} else {
		posterMediaID := item.PosterMediaID
		if posterMediaID == "" {
			posterMediaID = item.ThumbnailMediaID
		}
		if posterMediaID != "" {
			result.PosterURL = "/api/v1/media/" + url.PathEscape(posterMediaID) + "/thumbnail"
		}
	}
	if item.BackdropArtworkID != "" {
		result.BackdropURL = "/api/v1/catalog/artwork/" + url.PathEscape(item.BackdropArtworkID)
	}
	if includeEpisodes {
		result.Episodes = make([]catalogEpisodeJSON, 0, len(item.Episodes))
		for _, episode := range item.Episodes {
			value := catalogEpisodeJSON{ID: episode.ID, SeasonNumber: episode.SeasonNumber, EpisodeNumber: episode.EpisodeNumber, Title: episode.Title, MediaID: episode.MediaID, DurationMS: episode.DurationMS, Resolution: episode.Resolution, ProgressMS: episode.ProgressMS, Completed: episode.Completed}
			if episode.ThumbnailMediaID != "" {
				value.ThumbnailURL = "/api/v1/media/" + url.PathEscape(episode.ThumbnailMediaID) + "/thumbnail"
			}
			result.Episodes = append(result.Episodes, value)
		}
		if item.Kind == domain.CatalogKindMovie {
			result.Versions = make([]catalogVersionJSON, 0, len(item.Versions))
			for _, version := range item.Versions {
				result.Versions = append(result.Versions, catalogVersionJSON{
					MediaID: version.MediaID, Label: version.Label, FileSize: version.FileSize,
					DurationMS: version.DurationMS, Resolution: version.Resolution, VideoCodec: version.VideoCodec,
					AudioCodec: version.AudioCodec, AudioTrackCount: version.AudioTrackCount,
					ProgressMS: version.ProgressMS, Completed: version.Completed, Selected: version.Selected,
				})
			}
		}
	}
	return result
}

func presentCredits(values []domain.CatalogCredit) []catalogCreditJSON {
	result := make([]catalogCreditJSON, 0, len(values))
	for _, value := range values {
		credit := catalogCreditJSON{ProviderPersonID: value.ProviderPersonID, Name: value.Name,
			Character: value.Character, Department: value.Department, Job: value.Job, Order: value.Order}
		if value.ProfileArtworkID != "" {
			credit.ProfileURL = "/api/v1/catalog/artwork/" + url.PathEscape(value.ProfileArtworkID)
		}
		result = append(result, credit)
	}
	return result
}

type updateCatalogFavoriteRequest struct {
	Favorite     bool  `json:"favorite"`
	BaseRevision int64 `json:"base_revision"`
}

// UpdateFavorite 保存作品级收藏，不把状态绑定到特定清晰度文件。
func (h *CatalogHandler) UpdateFavorite(c *gin.Context) {
	service, ok := h.service.(catalogFavoriteUseCase)
	if !ok {
		response.Error(c, http.StatusNotImplemented, "CATALOG_FAVORITE_UNAVAILABLE", "catalog favorites are unavailable", nil)
		return
	}
	var request updateCatalogFavoriteRequest
	if err := apirequest.DecodeJSON(c, &request); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	value, err := service.UpdateFavorite(c.Request.Context(), c.Param("id"), c.GetString("user_id"), request.Favorite, request.BaseRevision)
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"catalog_item_id": value.CatalogItemID, "favorite": value.Favorite,
		"revision": value.Revision, "updated_at": value.UpdatedAt.Format(time.RFC3339Nano)})
}

func nonNilNamed(values []domain.CatalogNamedValue) []domain.CatalogNamedValue {
	if values == nil {
		return []domain.CatalogNamedValue{}
	}
	return values
}

// MetadataCandidates returns provider-neutral candidates already persisted for one work.
func (h *CatalogHandler) MetadataCandidates(c *gin.Context) {
	service, ok := h.service.(catalogMetadataUseCase)
	if !ok {
		response.Error(c, http.StatusNotImplemented, "METADATA_UNAVAILABLE", "metadata scraper is unavailable", nil)
		return
	}
	items, err := service.MetadataCandidates(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	result := make([]gin.H, 0, len(items))
	for _, item := range items {
		result = append(result, gin.H{
			"id": item.ID, "provider": item.Provider, "provider_item_id": item.ProviderItemID,
			"title": item.Title, "original_title": item.OriginalTitle, "year": item.Year,
			"overview": item.Overview, "score": item.Score, "reasons": item.Reasons,
		})
	}
	c.JSON(http.StatusOK, gin.H{"items": result})
}

// RefreshMetadata queues one catalog work for asynchronous scraping.
func (h *CatalogHandler) RefreshMetadata(c *gin.Context) {
	service, ok := h.service.(catalogMetadataUseCase)
	if !ok {
		response.Error(c, http.StatusNotImplemented, "METADATA_UNAVAILABLE", "metadata scraper is unavailable", nil)
		return
	}
	count, err := service.RefreshMetadata(c.Request.Context(), c.Param("id"), "")
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusAccepted, gin.H{"queued_count": count})
}

type refreshCatalogMetadataRequest struct {
	SourceID string `json:"source_id"`
}

// RefreshAllMetadata queues all works or one source for asynchronous scraping.
func (h *CatalogHandler) RefreshAllMetadata(c *gin.Context) {
	service, ok := h.service.(catalogMetadataUseCase)
	if !ok {
		response.Error(c, http.StatusNotImplemented, "METADATA_UNAVAILABLE", "metadata scraper is unavailable", nil)
		return
	}
	var request refreshCatalogMetadataRequest
	if c.Request.ContentLength != 0 {
		if err := apirequest.DecodeJSON(c, &request); err != nil {
			response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
			return
		}
	}
	count, err := service.RefreshMetadata(c.Request.Context(), "", request.SourceID)
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusAccepted, gin.H{"queued_count": count})
}

type selectCatalogIdentityRequest struct {
	Provider       string `json:"provider"`
	ProviderItemID string `json:"provider_item_id"`
	BaseRevision   int    `json:"base_revision"`
}

// SelectMetadataIdentity locks a user-selected provider identity.
func (h *CatalogHandler) SelectMetadataIdentity(c *gin.Context) {
	service, ok := h.service.(catalogMetadataUseCase)
	if !ok {
		response.Error(c, http.StatusNotImplemented, "METADATA_UNAVAILABLE", "metadata scraper is unavailable", nil)
		return
	}
	var request selectCatalogIdentityRequest
	if err := apirequest.DecodeJSON(c, &request); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	if err := service.SelectMetadataIdentity(c.Request.Context(), c.Param("id"), request.Provider,
		request.ProviderItemID, request.BaseRevision); err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

// MetadataProviders returns sanitized registered provider status.
func (h *CatalogHandler) MetadataProviders(c *gin.Context) {
	service, ok := h.service.(catalogMetadataUseCase)
	if !ok {
		response.Error(c, http.StatusNotImplemented, "METADATA_UNAVAILABLE", "metadata scraper is unavailable", nil)
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": service.MetadataProviders(c.Request.Context())})
}

// Artwork serves an authorized cached or provider-backed catalog image.
func (h *CatalogHandler) Artwork(c *gin.Context) {
	service, ok := h.service.(catalogMetadataUseCase)
	if !ok {
		response.Error(c, http.StatusNotImplemented, "METADATA_UNAVAILABLE", "metadata scraper is unavailable", nil)
		return
	}
	content, err := service.Artwork(c.Request.Context(), c.Param("id"), c.GetString("user_id"), c.GetHeader("If-None-Match"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.Header("ETag", content.ETag)
	c.Header("Cache-Control", "private, max-age=86400")
	if content.NotModified {
		c.Status(http.StatusNotModified)
		return
	}
	c.Data(http.StatusOK, content.MIMEType, content.Data)
}

func parseOptionalLimit(c *gin.Context) (int, bool) {
	raw, exists := c.GetQuery("limit")
	if !exists {
		return 0, true
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "limit 必须是整数", nil)
		return 0, false
	}
	return value, true
}
