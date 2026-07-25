package jobs

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/fsnotify/fsnotify"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func (s *AutoScanScheduler) openWatcher() error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	s.watcher = watcher
	return nil
}

func (s *AutoScanScheduler) consumeWatcher(ctx context.Context, watcher *fsnotify.Watcher) {
	for {
		select {
		case <-ctx.Done():
			return
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			s.logger.Error("目录监听错误", "error", err)
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			if event.Has(fsnotify.Chmod) && !event.Has(fsnotify.Write) &&
				!event.Has(fsnotify.Create) && !event.Has(fsnotify.Remove) && !event.Has(fsnotify.Rename) {
				continue
			}
			sourceID := s.lookupSource(event.Name)
			if sourceID == "" {
				continue
			}
			if event.Has(fsnotify.Create) {
				if info, err := os.Stat(event.Name); err == nil && info.IsDir() {
					_ = s.addWatchPath(sourceID, event.Name)
				}
			}
			s.scheduleSource(ctx, sourceID)
		}
	}
}

func (s *AutoScanScheduler) lookupSource(eventPath string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	clean := filepath.Clean(eventPath)
	if id, ok := s.sourceByWatchPath[clean]; ok {
		return id
	}
	dir := clean
	for {
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		if id, ok := s.sourceByWatchPath[parent]; ok {
			return id
		}
		dir = parent
	}
	for sourceID, root := range s.rootBySource {
		if pathIsWithinRoot(root, clean) {
			return sourceID
		}
	}
	return ""
}

func (s *AutoScanScheduler) syncWatches(enabled []domain.Source) error {
	if s.watcher == nil {
		return nil
	}
	desired := make(map[string]string, len(enabled))
	for _, source := range enabled {
		desired[source.ID] = filepath.Clean(source.RootPath)
	}

	s.mu.Lock()
	current := make(map[string]string, len(s.rootBySource))
	for id, root := range s.rootBySource {
		current[id] = root
	}
	s.mu.Unlock()

	for sourceID, root := range current {
		next, ok := desired[sourceID]
		if ok && next == root {
			continue
		}
		s.removeSourceWatches(sourceID)
	}
	for sourceID, root := range desired {
		if current[sourceID] == root {
			continue
		}
		if err := s.watchSourceTree(sourceID, root); err != nil {
			s.logger.Error("监视媒体源目录失败", "source_id", sourceID, "root", root, "error", err)
		}
	}
	return nil
}

func (s *AutoScanScheduler) watchSourceTree(sourceID, root string) error {
	info, err := os.Stat(root)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("根路径不是目录: %s", root)
	}
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			s.logger.Warn("遍历媒体源子目录失败", "path", path, "error", walkErr)
			if entry != nil && entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !entry.IsDir() {
			return nil
		}
		return s.addWatchPath(sourceID, path)
	})
	if err != nil {
		s.removeSourceWatches(sourceID)
		return err
	}
	s.mu.Lock()
	s.rootBySource[sourceID] = root
	s.mu.Unlock()
	return nil
}

func (s *AutoScanScheduler) addWatchPath(sourceID, path string) error {
	if s.watcher == nil {
		return nil
	}
	clean := filepath.Clean(path)
	if err := s.watcher.Add(clean); err != nil {
		return err
	}
	s.mu.Lock()
	s.sourceByWatchPath[clean] = sourceID
	s.mu.Unlock()
	return nil
}

func (s *AutoScanScheduler) removeSourceWatches(sourceID string) {
	if s.watcher == nil {
		return
	}
	s.mu.Lock()
	var paths []string
	for path, id := range s.sourceByWatchPath {
		if id == sourceID {
			paths = append(paths, path)
			delete(s.sourceByWatchPath, path)
		}
	}
	delete(s.rootBySource, sourceID)
	if timer, ok := s.debounceTimers[sourceID]; ok {
		if timer.timer.Stop() {
			timer.done.Do(s.timerWG.Done)
		}
		delete(s.debounceTimers, sourceID)
	}
	s.mu.Unlock()
	for _, path := range paths {
		_ = s.watcher.Remove(path)
	}
}

func (s *AutoScanScheduler) shutdown() {
	s.mu.Lock()
	s.sourceByWatchPath = make(map[string]string)
	s.rootBySource = make(map[string]string)
	watcher := s.watcher
	s.watcher = nil
	s.mu.Unlock()
	if watcher != nil {
		_ = watcher.Close()
	}
}

func pathIsWithinRoot(root, candidate string) bool {
	root = filepath.Clean(root)
	candidate = filepath.Clean(candidate)
	if runtime.GOOS == "windows" {
		root = strings.ToLower(root)
		candidate = strings.ToLower(candidate)
	}
	if root == candidate {
		return true
	}
	return strings.HasPrefix(candidate, root+string(filepath.Separator))
}
