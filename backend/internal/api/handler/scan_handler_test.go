package handler

import (
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestPresentScanJobIncludesProcessingSummary(t *testing.T) {
	response := presentScanJob(domain.ScanJob{Processing: domain.ProcessingSummary{
		Status: "completed_with_errors", Total: 3, Ready: 2, Failed: 1,
	}})
	if response.Processing.Status != "completed_with_errors" || response.Processing.Total != 3 ||
		response.Processing.Ready != 2 || response.Processing.Failed != 1 {
		t.Fatalf("processing response = %#v", response.Processing)
	}
}

func TestPresentScanJobDefaultsProcessingToPending(t *testing.T) {
	response := presentScanJob(domain.ScanJob{})
	if response.Processing.Status != "pending" {
		t.Fatalf("processing status = %q", response.Processing.Status)
	}
}
