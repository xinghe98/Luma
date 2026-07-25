// Package metadata coordinates registered scraper providers without exposing provider-specific data.
package metadata

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"sync"

	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

var providerIDPattern = regexp.MustCompile(`^[a-z][a-z0-9_-]{1,31}$`)

// Registry owns the process-local set of validated scraper providers.
type Registry struct {
	mu        sync.RWMutex
	providers map[string]scraper.Provider
	order     []string
}

// NewRegistry creates an empty provider registry.
func NewRegistry() *Registry {
	return &Registry{providers: make(map[string]scraper.Provider)}
}

// Register validates and adds a provider. Duplicate IDs and capability mismatches fail.
func (r *Registry) Register(provider scraper.Provider) error {
	if provider == nil {
		return errors.New("刮削 Provider 不能为空")
	}
	descriptor := provider.Descriptor()
	if !providerIDPattern.MatchString(descriptor.ID) {
		return fmt.Errorf("非法刮削 Provider ID %q", descriptor.ID)
	}
	if descriptor.Name == "" || len(descriptor.Kinds) == 0 {
		return fmt.Errorf("刮削 Provider %q 缺少名称或媒体类型", descriptor.ID)
	}
	for _, kind := range descriptor.Kinds {
		if kind != scraper.MediaKindMovie && kind != scraper.MediaKindSeries {
			return fmt.Errorf("刮削 Provider %q 声明非法媒体类型 %q", descriptor.ID, kind)
		}
	}
	if err := validateCapabilities(provider, descriptor); err != nil {
		return err
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, exists := r.providers[descriptor.ID]; exists {
		return fmt.Errorf("刮削 Provider %q 重复注册", descriptor.ID)
	}
	r.providers[descriptor.ID] = provider
	r.order = append(r.order, descriptor.ID)
	return nil
}

// Provider returns a registered provider by stable ID.
func (r *Registry) Provider(id string) (scraper.Provider, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	value, ok := r.providers[id]
	return value, ok
}

// ProvidersFor returns providers supporting a kind and capability in registration order.
func (r *Registry) ProvidersFor(kind scraper.MediaKind, capability scraper.Capability) []scraper.Provider {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]scraper.Provider, 0, len(r.order))
	for _, id := range r.order {
		provider := r.providers[id]
		descriptor := provider.Descriptor()
		if slices.Contains(descriptor.Kinds, kind) && slices.Contains(descriptor.Capabilities, capability) {
			result = append(result, provider)
		}
	}
	return result
}

// Descriptors returns immutable provider descriptions in registration order.
func (r *Registry) Descriptors() []scraper.Descriptor {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]scraper.Descriptor, 0, len(r.order))
	for _, id := range r.order {
		result = append(result, r.providers[id].Descriptor())
	}
	return result
}

func validateCapabilities(provider scraper.Provider, descriptor scraper.Descriptor) error {
	checks := []struct {
		capability  scraper.Capability
		implemented bool
	}{
		{scraper.CapabilitySearch, implements[scraper.Searcher](provider)},
		{scraper.CapabilityExternalID, implements[scraper.ExternalIDResolver](provider)},
		{scraper.CapabilityWork, implements[scraper.WorkFetcher](provider)},
		{scraper.CapabilitySeason, implements[scraper.SeasonFetcher](provider)},
		{scraper.CapabilityEpisode, implements[scraper.EpisodeFetcher](provider)},
		{scraper.CapabilityArtwork, implements[scraper.ArtworkFetcher](provider)},
		{scraper.CapabilitySidecar, implements[scraper.SidecarParser](provider)},
		{scraper.CapabilityHealth, implements[scraper.HealthChecker](provider)},
	}
	for _, check := range checks {
		declared := slices.Contains(descriptor.Capabilities, check.capability)
		if declared != check.implemented {
			return fmt.Errorf("刮削 Provider %q 的 %s 能力声明与接口实现不一致", descriptor.ID, check.capability)
		}
	}
	return nil
}

func implements[T any](provider scraper.Provider) bool {
	_, ok := provider.(T)
	return ok
}
