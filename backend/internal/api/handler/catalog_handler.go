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
	Issues(context.Context, int) ([]domain.CatalogIssue, error)
	UpdateMatch(context.Context, domain.UpdateCatalogMatchCommand) error
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
	ID              string               `json:"id"`
	SourceID        string               `json:"source_id"`
	Kind            string               `json:"kind"`
	Title           string               `json:"title"`
	Year            *int                 `json:"year"`
	MatchStatus     string               `json:"match_status"`
	MediaCount      int                  `json:"media_count"`
	EpisodeCount    int                  `json:"episode_count"`
	CompletedCount  int                  `json:"completed_count"`
	PlayableMediaID string               `json:"playable_media_id"`
	ThumbnailURL    string               `json:"thumbnail_url"`
	PosterURL       string               `json:"poster_url"`
	DurationMS      *int64               `json:"duration_ms"`
	Resolution      string               `json:"resolution"`
	ProgressMS      int64                `json:"progress_ms"`
	Completed       bool                 `json:"completed"`
	UpdatedAt       string               `json:"updated_at"`
	Episodes        []catalogEpisodeJSON `json:"episodes,omitempty"`
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

func (h *CatalogHandler) Issues(c *gin.Context) {
	limit, ok := parseOptionalLimit(c)
	if !ok {
		return
	}
	items, err := h.service.Issues(c.Request.Context(), limit)
	if err != nil {
		response.FromError(c, err)
		return
	}
	result := make([]catalogIssueJSON, 0, len(items))
	for _, item := range items {
		result = append(result, catalogIssueJSON{MediaID: item.MediaID, Filename: item.Filename,
			SourceID: item.SourceID, LibraryKind: item.LibraryKind, SuggestedTitle: item.SuggestedTitle,
			SeasonNumber: item.SeasonNumber, EpisodeNumber: item.EpisodeNumber})
	}
	c.JSON(http.StatusOK, gin.H{"items": result})
}

type catalogIssueJSON struct {
	MediaID        string `json:"media_id"`
	Filename       string `json:"filename"`
	SourceID       string `json:"source_id"`
	LibraryKind    string `json:"library_kind"`
	SuggestedTitle string `json:"suggested_title"`
	SeasonNumber   *int   `json:"season_number"`
	EpisodeNumber  *int   `json:"episode_number"`
}

type updateCatalogMatchRequest struct {
	Kind          string `json:"kind"`
	Title         string `json:"title"`
	Year          *int   `json:"year"`
	SeasonNumber  *int   `json:"season_number"`
	EpisodeNumber *int   `json:"episode_number"`
	Ignored       bool   `json:"ignored"`
}

func (h *CatalogHandler) UpdateMatch(c *gin.Context) {
	var request updateCatalogMatchRequest
	if err := apirequest.DecodeJSON(c, &request); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", err.Error(), nil)
		return
	}
	err := h.service.UpdateMatch(c.Request.Context(), domain.UpdateCatalogMatchCommand{MediaID: c.Param("id"), Kind: request.Kind, Title: request.Title, Year: request.Year, SeasonNumber: request.SeasonNumber, EpisodeNumber: request.EpisodeNumber, Ignored: request.Ignored})
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func presentCatalog(item domain.CatalogItem, includeEpisodes bool) catalogItemJSON {
	result := catalogItemJSON{ID: item.ID, SourceID: item.SourceID, Kind: item.Kind, Title: item.Title, Year: item.Year,
		MatchStatus: item.MatchStatus, MediaCount: item.MediaCount, EpisodeCount: item.EpisodeCount, CompletedCount: item.CompletedCount,
		PlayableMediaID: item.PlayableMediaID, DurationMS: item.DurationMS, Resolution: item.Resolution, ProgressMS: item.ProgressMS, Completed: item.Completed,
		UpdatedAt: item.UpdatedAt.UTC().Format(time.RFC3339Nano)}
	if item.ThumbnailMediaID != "" {
		result.ThumbnailURL = "/api/v1/media/" + url.PathEscape(item.ThumbnailMediaID) + "/thumbnail"
	}
	posterMediaID := item.PosterMediaID
	if posterMediaID == "" {
		posterMediaID = item.ThumbnailMediaID
	}
	if posterMediaID != "" {
		result.PosterURL = "/api/v1/media/" + url.PathEscape(posterMediaID) + "/thumbnail"
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
	}
	return result
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
