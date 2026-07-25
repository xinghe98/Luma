package handler

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ScanUseCase 定义扫描任务 Handler 所需的业务能力。
type ScanUseCase interface {
	// Start 创建异步媒体源扫描任务。
	Start(context.Context, string) (domain.ScanJob, error)
	// Get 返回指定扫描任务。
	Get(context.Context, string) (domain.ScanJob, error)
	// Latest 返回指定媒体源或全局最近扫描任务。
	Latest(context.Context, string) (domain.ScanJob, error)
}

// ScanHandler 将扫描任务业务用例适配为 HTTP API。
type ScanHandler struct {
	// service 是注入的扫描任务业务用例。
	service ScanUseCase
}

// NewScanHandler 使用扫描业务用例创建 Handler。
func NewScanHandler(service ScanUseCase) (*ScanHandler, error) {
	if service == nil {
		return nil, errors.New("扫描业务用例不能为空")
	}
	return &ScanHandler{service: service}, nil
}

// scanJobResponse 表示扫描任务及其进度的 API DTO。
// scanJobResponse 是扫描任务 API 响应，字段对应 domain.ScanJob / scan_jobs。
type scanJobResponse struct {
	// ID 对应 scan_jobs.id。
	ID string `json:"id"`
	// SourceID 对应 scan_jobs.source_id。
	SourceID string `json:"source_id"`
	// Status 对应 scan_jobs.status。
	Status string `json:"status"`
	// Phase 对应 scan_jobs.phase。
	Phase string `json:"phase"`
	// DiscoveredCount 对应 scan_jobs.discovered_count。
	DiscoveredCount int64 `json:"discovered_count"`
	// ProcessedCount 对应 scan_jobs.processed_count。
	ProcessedCount int64 `json:"processed_count"`
	// FailedCount 对应 scan_jobs.failed_count。
	FailedCount int64 `json:"failed_count"`
	// StartedAt 对应 scan_jobs.started_at_ms 的 ISO 8601 UTC；未开始时省略。
	StartedAt *string `json:"started_at,omitempty"`
	// FinishedAt 对应 scan_jobs.finished_at_ms 的 ISO 8601 UTC；进行中省略。
	FinishedAt *string `json:"finished_at,omitempty"`
	// ErrorCode 对应 scan_jobs.error_code。
	ErrorCode string `json:"error_code,omitempty"`
	// ErrorMessage 对应 scan_jobs.error_message，不含真实绝对路径。
	ErrorMessage string `json:"error_message,omitempty"`
	// CreatedAt 对应 scan_jobs.created_at_ms 的 ISO 8601 UTC。
	CreatedAt string `json:"created_at"`
	// UpdatedAt 对应 scan_jobs.updated_at_ms 的 ISO 8601 UTC。
	UpdatedAt string `json:"updated_at"`
	// Processing 由 media_items 按 last_seen_scan_id 聚合的处理进度。
	Processing processingSummaryResponse `json:"processing"`
	// Metadata 由本次扫描关联的影视资料任务聚合的进度。
	Metadata metadataSummaryResponse `json:"metadata"`
}

// metadataSummaryResponse 对应 domain.MetadataSummary。
type metadataSummaryResponse struct {
	// Status 为 waiting、running、completed 或 completed_with_errors。
	Status string `json:"status"`
	// Total 本次扫描需处理的作品数。
	Total int64 `json:"total"`
	// Pending 等待刮削的作品数。
	Pending int64 `json:"pending"`
	// Refreshing 正在联网匹配的作品数。
	Refreshing int64 `json:"refreshing"`
	// Ready 已写入资料的作品数。
	Ready int64 `json:"ready"`
	// Unmatched 无可自动采用候选的作品数。
	Unmatched int64 `json:"unmatched"`
	// Failed 最终失败的作品数。
	Failed int64 `json:"failed"`
}

// processingSummaryResponse 对应 domain.ProcessingSummary。
type processingSummaryResponse struct {
	// Status 为 pending、running、completed 或 completed_with_errors。
	Status string `json:"status"`
	// Total 本次扫描确认存在的媒体总数。
	Total int64 `json:"total"`
	// Discovered 仍为 discovered 的媒体数。
	Discovered int64 `json:"discovered"`
	// Probing 仍为 probing 的媒体数。
	Probing int64 `json:"probing"`
	// Thumbnailing 仍为 thumbnailing 的媒体数。
	Thumbnailing int64 `json:"thumbnailing"`
	// Ready 已 ready 的媒体数。
	Ready int64 `json:"ready"`
	// Failed 最终 failed 的媒体数。
	Failed int64 `json:"failed"`
}

// Start 处理 POST /api/v1/sources/:id/scan 请求并立即返回 202。
func (h *ScanHandler) Start(c *gin.Context) {
	job, err := h.service.Start(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusAccepted, presentScanJob(job))
}

// Get 处理 GET /api/v1/scan-jobs/:id 请求。
func (h *ScanHandler) Get(c *gin.Context) {
	job, err := h.service.Get(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentScanJob(job))
}

// Latest 处理 GET /api/v1/scan-jobs/latest 请求。
func (h *ScanHandler) Latest(c *gin.Context) {
	job, err := h.service.Latest(c.Request.Context(), c.Query("source_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentScanJob(job))
}

// presentScanJob 将扫描任务转换为 ISO 8601 时间格式的 API DTO。
func presentScanJob(job domain.ScanJob) scanJobResponse {
	result := scanJobResponse{
		ID: job.ID, SourceID: job.SourceID, Status: job.Status, Phase: job.Phase,
		DiscoveredCount: job.DiscoveredCount, ProcessedCount: job.ProcessedCount,
		FailedCount: job.FailedCount, ErrorCode: job.ErrorCode, ErrorMessage: job.ErrorMessage,
		CreatedAt:  job.CreatedAt.UTC().Format(time.RFC3339Nano),
		UpdatedAt:  job.UpdatedAt.UTC().Format(time.RFC3339Nano),
		Processing: presentProcessingSummary(job.Processing),
		Metadata:   presentMetadataSummary(job.Metadata),
	}
	if job.StartedAt != nil {
		value := job.StartedAt.UTC().Format(time.RFC3339Nano)
		result.StartedAt = &value
	}
	if job.FinishedAt != nil {
		value := job.FinishedAt.UTC().Format(time.RFC3339Nano)
		result.FinishedAt = &value
	}
	return result
}

// presentMetadataSummary 为尚未建立资料运行的新扫描保留等待态。
func presentMetadataSummary(summary domain.MetadataSummary) metadataSummaryResponse {
	status := summary.Status
	if status == "" {
		status = "waiting"
	}
	return metadataSummaryResponse{Status: status, Total: summary.Total, Pending: summary.Pending,
		Refreshing: summary.Refreshing, Ready: summary.Ready, Unmatched: summary.Unmatched, Failed: summary.Failed}
}

func presentProcessingSummary(summary domain.ProcessingSummary) processingSummaryResponse {
	status := summary.Status
	if status == "" {
		status = "pending"
	}
	return processingSummaryResponse{
		Status: status, Total: summary.Total, Discovered: summary.Discovered,
		Probing: summary.Probing, Thumbnailing: summary.Thumbnailing,
		Ready: summary.Ready, Failed: summary.Failed,
	}
}
