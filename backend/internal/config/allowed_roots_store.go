package config

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"gopkg.in/yaml.v3"
)

// AllowedRootsUpdate records one persisted allowed-roots mutation so a caller
// can restore it when a later provisioning step fails.
type AllowedRootsUpdate struct {
	Previous []string
	Current  []string
}

// AllowedRootsStore is the sole writer for security.allowed_roots. Keeping
// this responsibility here prevents HTTP handlers from editing YAML directly.
type AllowedRootsStore struct {
	path string
	mu   sync.Mutex
}

func NewAllowedRootsStore(path string) (*AllowedRootsStore, error) {
	if strings.TrimSpace(path) == "" {
		return nil, fmt.Errorf("config path is required")
	}
	return &AllowedRootsStore{path: path}, nil
}

// List returns the currently configured, resolved media roots without
// modifying the configuration file. Callers must keep these server-local
// paths within an administrator-only boundary.
func (s *AllowedRootsStore) List() ([]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg, err := Load(s.path)
	if err != nil {
		return nil, err
	}
	return append([]string(nil), cfg.Security.AllowedRoots...), nil
}

// Add validates the complete resulting configuration, writes it atomically,
// and returns both root sets for the in-memory policy update.
func (s *AllowedRootsStore) Add(root string) (AllowedRootsUpdate, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.update(func(roots []string) []string {
		for _, item := range roots {
			if samePath(item, root) {
				return roots
			}
		}
		return append(roots, root)
	})
}

// Restore reverses an update made by Add. It is used only while the
// provisioning service still holds its operation lock.
func (s *AllowedRootsStore) Restore(update AllowedRootsUpdate) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err := s.writeRoots(update.Previous)
	return err
}

func (s *AllowedRootsStore) update(transform func([]string) []string) (AllowedRootsUpdate, error) {
	cfg, err := Load(s.path)
	if err != nil {
		return AllowedRootsUpdate{}, err
	}
	previous := append([]string(nil), cfg.Security.AllowedRoots...)
	current := transform(append([]string(nil), previous...))
	if err := Validate(withAllowedRoots(cfg, current)); err != nil {
		return AllowedRootsUpdate{}, err
	}
	if err := s.replaceRoots(current); err != nil {
		return AllowedRootsUpdate{}, err
	}
	return AllowedRootsUpdate{Previous: previous, Current: current}, nil
}

func (s *AllowedRootsStore) writeRoots(roots []string) (AllowedRootsUpdate, error) {
	cfg, err := Load(s.path)
	if err != nil {
		return AllowedRootsUpdate{}, err
	}
	previous := append([]string(nil), cfg.Security.AllowedRoots...)
	if err := Validate(withAllowedRoots(cfg, roots)); err != nil {
		return AllowedRootsUpdate{}, err
	}
	if err := s.replaceRoots(roots); err != nil {
		return AllowedRootsUpdate{}, err
	}
	return AllowedRootsUpdate{Previous: previous, Current: append([]string(nil), roots...)}, nil
}

func withAllowedRoots(cfg Config, roots []string) Config {
	cfg.Security.AllowedRoots = append([]string(nil), roots...)
	return cfg
}

func (s *AllowedRootsStore) replaceRoots(roots []string) error {
	raw, err := os.ReadFile(s.path)
	if err != nil {
		return fmt.Errorf("read config: %w", err)
	}
	var document yaml.Node
	if err := yaml.Unmarshal(raw, &document); err != nil {
		return fmt.Errorf("decode config document: %w", err)
	}
	sequence, err := allowedRootsNode(&document)
	if err != nil {
		return err
	}
	sequence.Content = sequence.Content[:0]
	for _, root := range roots {
		sequence.Content = append(sequence.Content, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: root})
	}
	var encoded bytes.Buffer
	encoder := yaml.NewEncoder(&encoded)
	encoder.SetIndent(2)
	if err := encoder.Encode(&document); err != nil {
		return fmt.Errorf("encode config document: %w", err)
	}
	if err := encoder.Close(); err != nil {
		return fmt.Errorf("close config encoder: %w", err)
	}
	info, err := os.Stat(s.path)
	if err != nil {
		return fmt.Errorf("stat config: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(s.path), ".luma-config-*.yaml")
	if err != nil {
		return fmt.Errorf("create temporary config: %w", err)
	}
	temporaryName := temporary.Name()
	defer os.Remove(temporaryName)
	if _, err := temporary.Write(encoded.Bytes()); err != nil {
		temporary.Close()
		return fmt.Errorf("write temporary config: %w", err)
	}
	if err := temporary.Chmod(info.Mode()); err != nil {
		temporary.Close()
		return fmt.Errorf("set temporary config permissions: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("sync temporary config: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close temporary config: %w", err)
	}
	if err := os.Rename(temporaryName, s.path); err != nil {
		return fmt.Errorf("replace config atomically: %w", err)
	}
	return nil
}

func allowedRootsNode(document *yaml.Node) (*yaml.Node, error) {
	if document.Kind != yaml.DocumentNode || len(document.Content) != 1 {
		return nil, fmt.Errorf("config document must contain one mapping")
	}
	root := document.Content[0]
	security := mappingValue(root, "security")
	if security == nil || security.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("config.security is required")
	}
	roots := mappingValue(security, "allowed_roots")
	if roots == nil || roots.Kind != yaml.SequenceNode {
		return nil, fmt.Errorf("config.security.allowed_roots must be a sequence")
	}
	return roots, nil
}

func mappingValue(mapping *yaml.Node, key string) *yaml.Node {
	for index := 0; index+1 < len(mapping.Content); index += 2 {
		if mapping.Content[index].Value == key {
			return mapping.Content[index+1]
		}
	}
	return nil
}

func samePath(left, right string) bool {
	left, right = filepath.Clean(left), filepath.Clean(right)
	if runtime.GOOS == "windows" {
		return strings.EqualFold(left, right)
	}
	return left == right
}
