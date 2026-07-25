// 作品库同步信号保留成功扫描的上下文，供同步完成后立即安排资料刮削。
package jobs

import "sync"

// CatalogSyncEvent 表示一次已提交媒体扫描需要驱动的后续作品库整理。
type CatalogSyncEvent struct {
	ScanID   string
	SourceID string
}

// CatalogSyncSignal 在合并唤醒的同时保留每个扫描任务，避免短时间连续扫描丢失关联关系。
type CatalogSyncSignal struct {
	mu      sync.Mutex
	pending map[string]CatalogSyncEvent
	signal  *Signal
}

// NewCatalogSyncSignal 创建用于扫描后同步的事件信号。
func NewCatalogSyncSignal() *CatalogSyncSignal {
	return &CatalogSyncSignal{pending: make(map[string]CatalogSyncEvent), signal: NewSignal()}
}

// Notify 记录一个成功提交的扫描并唤醒同步器。
func (s *CatalogSyncSignal) Notify(event CatalogSyncEvent) {
	if event.ScanID == "" || event.SourceID == "" {
		return
	}
	s.mu.Lock()
	s.pending[event.ScanID] = event
	s.mu.Unlock()
	s.signal.Notify()
}

// C 返回合并后的唤醒通道。
func (s *CatalogSyncSignal) C() <-chan struct{} { return s.signal.C() }

// Take 取走当前累积的扫描事件。
func (s *CatalogSyncSignal) Take() []CatalogSyncEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	result := make([]CatalogSyncEvent, 0, len(s.pending))
	for _, event := range s.pending {
		result = append(result, event)
	}
	s.pending = make(map[string]CatalogSyncEvent)
	return result
}
