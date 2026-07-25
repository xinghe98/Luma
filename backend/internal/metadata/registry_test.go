// Registry tests enforce the public scraper capability contract.
package metadata

import (
	"context"
	"testing"

	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

type testProvider struct {
	descriptor scraper.Descriptor
}

func (p testProvider) Descriptor() scraper.Descriptor { return p.descriptor }

type searchProvider struct{ testProvider }

func (p searchProvider) Search(context.Context, scraper.SearchRequest) (scraper.SearchPage, error) {
	return scraper.SearchPage{}, nil
}

func TestRegistryValidatesCapabilitiesAndDuplicates(t *testing.T) {
	registry := NewRegistry()
	provider := searchProvider{testProvider{descriptor: scraper.Descriptor{
		ID: "test", Name: "Test", Kinds: []scraper.MediaKind{scraper.MediaKindMovie},
		Capabilities: []scraper.Capability{scraper.CapabilitySearch},
	}}}
	if err := registry.Register(provider); err != nil {
		t.Fatal(err)
	}
	if err := registry.Register(provider); err == nil {
		t.Fatal("expected duplicate provider error")
	}
	bad := searchProvider{testProvider{descriptor: scraper.Descriptor{
		ID: "bad", Name: "Bad", Kinds: []scraper.MediaKind{scraper.MediaKindMovie},
	}}}
	if err := NewRegistry().Register(bad); err == nil {
		t.Fatal("expected undeclared capability error")
	}
}
