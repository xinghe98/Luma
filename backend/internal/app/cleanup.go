package app

import (
	"errors"
	"fmt"
	"sync"
)

// cleanupEntry 表示一个带资源名称的清理动作。
type cleanupEntry struct {
	// name 用于在清理失败时补充资源上下文。
	name string
	// run 执行具体资源释放操作。
	run func() error
}

// cleanupStack 以线程安全、幂等方式按逆序执行资源清理。
type cleanupStack struct {
	// mu 保护清理动作集合。
	mu sync.Mutex
	// once 确保全部清理动作最多执行一次。
	once sync.Once
	// entries 按资源创建顺序保存清理动作。
	entries []cleanupEntry
	// err 缓存第一次清理得到的聚合错误。
	err error
}

// Push 按资源创建顺序登记一个清理动作。
func (s *cleanupStack) Push(name string, cleanup func() error) {
	if cleanup == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.entries = append(s.entries, cleanupEntry{name: name, run: cleanup})
}

// Close 按登记顺序的反方向执行清理，并聚合所有错误。
func (s *cleanupStack) Close() error {
	s.once.Do(func() {
		s.mu.Lock()
		entries := append([]cleanupEntry(nil), s.entries...)
		s.entries = nil
		s.mu.Unlock()

		var cleanupErrors []error
		for i := len(entries) - 1; i >= 0; i-- {
			if err := entries[i].run(); err != nil {
				cleanupErrors = append(cleanupErrors, fmt.Errorf("close %s: %w", entries[i].name, err))
			}
		}
		s.err = errors.Join(cleanupErrors...)
	})
	return s.err
}
