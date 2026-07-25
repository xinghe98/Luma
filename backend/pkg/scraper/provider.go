// Package scraper defines the provider-neutral contract used by Luma metadata scrapers.
// Implementations may perform network or sidecar IO, but must not depend on Luma persistence.
package scraper

import (
	"context"
	"fmt"
	"io"
	"time"
)

// MediaKind identifies the provider-neutral type of a catalog work.
type MediaKind string

const (
	MediaKindMovie  MediaKind = "movie"
	MediaKindSeries MediaKind = "series"
)

// Capability identifies an optional provider operation.
type Capability string

const (
	CapabilitySearch     Capability = "search"
	CapabilityExternalID Capability = "external_id"
	CapabilityWork       Capability = "work"
	CapabilitySeason     Capability = "season"
	CapabilityEpisode    Capability = "episode"
	CapabilityArtwork    Capability = "artwork"
	CapabilitySidecar    Capability = "sidecar"
	CapabilityHealth     Capability = "health"
)

// Descriptor describes a stable provider identity and its implemented capabilities.
type Descriptor struct {
	ID           string
	Name         string
	Kinds        []MediaKind
	Capabilities []Capability
}

// Locale controls localized provider responses.
type Locale struct {
	Language          string
	Region            string
	FallbackLanguages []string
}

// Provider is the mandatory base interface for every scraper registered with Luma.
type Provider interface {
	// Descriptor returns immutable registration metadata. IDs are persisted and must stay stable.
	Descriptor() Descriptor
}

// SearchRequest contains one provider search query and optional disambiguation hints.
type SearchRequest struct {
	Kind    MediaKind
	Query   string
	Year    *int
	Runtime *time.Duration
	Locale  Locale
	Limit   int
}

// SearchPage is a bounded page of normalized provider candidates.
type SearchPage struct {
	Items []Candidate
}

// Candidate is a provider-neutral possible work identity.
type Candidate struct {
	ProviderID        string
	ProviderItemID    string
	Kind              MediaKind
	Title             string
	OriginalTitle     string
	AlternativeTitles []string
	ReleaseDate       string
	Overview          string
	Popularity        float64
	ExternalIDs       map[string]string
	Poster            *ArtworkRef
	Backdrop          *ArtworkRef
}

// Searcher finds work identities. It must honor context cancellation.
type Searcher interface {
	Provider
	Search(context.Context, SearchRequest) (SearchPage, error)
}

// ExternalIDRequest asks a provider to resolve an external database identifier.
type ExternalIDRequest struct {
	Kind   MediaKind
	Source string
	Value  string
	Locale Locale
}

// ExternalIDResolver maps IMDb, TVDb, or similar IDs into provider candidates.
type ExternalIDResolver interface {
	Provider
	ResolveExternalID(context.Context, ExternalIDRequest) ([]Candidate, error)
}

// WorkRequest identifies a provider work and requested locale.
type WorkRequest struct {
	Kind           MediaKind
	ProviderItemID string
	Locale         Locale
}

// NamedValue represents a provider-neutral genre, country, or company.
type NamedValue struct {
	ID   string `json:"id,omitempty"`
	Name string `json:"name"`
}

// Credit describes a cast or crew contribution.
type Credit struct {
	ProviderPersonID string      `json:"provider_person_id,omitempty"`
	Name             string      `json:"name"`
	Character        string      `json:"character,omitempty"`
	Department       string      `json:"department,omitempty"`
	Job              string      `json:"job,omitempty"`
	Order            int         `json:"order"`
	Profile          *ArtworkRef `json:"profile,omitempty"`
}

// SeasonSummary describes a provider season without creating local playable episodes.
type SeasonSummary struct {
	ProviderSeasonID string
	SeasonNumber     int
	Title            string
	Overview         string
	AirDate          string
	EpisodeCount     int
	Poster           *ArtworkRef
}

// WorkMetadata is the normalized rich metadata returned by a work provider.
type WorkMetadata struct {
	ProviderID        string
	ProviderItemID    string
	Kind              MediaKind
	Title             string
	OriginalTitle     string
	AlternativeTitles []string
	Overview          string
	Tagline           string
	ReleaseDate       string
	EndDate           string
	Runtime           *time.Duration
	Certification     string
	CommunityRating   *float64
	VoteCount         int
	Genres            []NamedValue
	Countries         []NamedValue
	Studios           []NamedValue
	ExternalIDs       map[string]string
	Credits           []Credit
	Seasons           []SeasonSummary
	Poster            *ArtworkRef
	Backdrop          *ArtworkRef
}

// WorkFetcher returns normalized details for a known provider identity.
type WorkFetcher interface {
	Provider
	FetchWork(context.Context, WorkRequest) (WorkMetadata, error)
}

// SeasonRequest identifies a series season.
type SeasonRequest struct {
	ProviderItemID string
	SeasonNumber   int
	Locale         Locale
}

// EpisodeMetadata describes one provider episode.
type EpisodeMetadata struct {
	ProviderEpisodeID string
	SeasonNumber      int
	EpisodeNumber     int
	Title             string
	Overview          string
	AirDate           string
	Runtime           *time.Duration
	CommunityRating   *float64
	Still             *ArtworkRef
}

// SeasonMetadata contains one season and its provider episodes.
type SeasonMetadata struct {
	ProviderSeasonID string
	SeasonNumber     int
	Title            string
	Overview         string
	AirDate          string
	Poster           *ArtworkRef
	Episodes         []EpisodeMetadata
}

// SeasonFetcher returns metadata for one series season.
type SeasonFetcher interface {
	Provider
	FetchSeason(context.Context, SeasonRequest) (SeasonMetadata, error)
}

// EpisodeRequest identifies one series episode.
type EpisodeRequest struct {
	ProviderItemID string
	SeasonNumber   int
	EpisodeNumber  int
	Locale         Locale
}

// EpisodeFetcher returns metadata for one episode when the provider supports direct lookup.
type EpisodeFetcher interface {
	Provider
	FetchEpisode(context.Context, EpisodeRequest) (EpisodeMetadata, error)
}

// ArtworkRef is an opaque provider-owned image reference.
type ArtworkRef struct {
	ProviderID string `json:"provider"`
	Key        string `json:"key"`
}

// ArtworkRequest asks the owning provider for image bytes.
type ArtworkRequest struct {
	Reference ArtworkRef
	MaxWidth  int
}

// ArtworkContent streams one provider image. Callers must close Body.
type ArtworkContent struct {
	Body          io.ReadCloser
	MIMEType      string
	ContentLength int64
	ETag          string
}

// ArtworkFetcher opens provider artwork without exposing credential-bearing URLs.
type ArtworkFetcher interface {
	Provider
	OpenArtwork(context.Context, ArtworkRequest) (ArtworkContent, error)
}

// SidecarRequest contains a safely opened local sidecar and structural context.
type SidecarRequest struct {
	Kind          MediaKind
	Filename      string
	SeasonNumber  *int
	EpisodeNumber *int
	Body          io.Reader
	Locale        Locale
}

// MetadataPatch represents partial sidecar metadata; nil fields are absent.
type MetadataPatch struct {
	Title           *string
	OriginalTitle   *string
	Overview        *string
	Tagline         *string
	ReleaseDate     *string
	Year            *int
	Runtime         *time.Duration
	Certification   *string
	CommunityRating *float64
	Genres          *[]NamedValue
	ExternalIDs     map[string]string
	Poster          *ArtworkRef
	Backdrop        *ArtworkRef
}

// SidecarParser parses a local sidecar supplied by Luma and must not open paths itself.
type SidecarParser interface {
	Provider
	ParseSidecar(context.Context, SidecarRequest) (MetadataPatch, error)
}

// HealthResult reports provider availability without exposing credentials.
type HealthResult struct {
	Available bool
	Message   string
	CheckedAt time.Time
}

// HealthChecker checks provider connectivity and credentials.
type HealthChecker interface {
	Provider
	CheckHealth(context.Context) HealthResult
}

// ErrorKind classifies retry and user-action behavior.
type ErrorKind string

const (
	ErrorUnauthorized    ErrorKind = "unauthorized"
	ErrorNotFound        ErrorKind = "not_found"
	ErrorRateLimited     ErrorKind = "rate_limited"
	ErrorTemporary       ErrorKind = "temporary"
	ErrorInvalidResponse ErrorKind = "invalid_response"
	ErrorUnsupported     ErrorKind = "unsupported"
)

// ProviderError is a sanitized provider failure. Err must never contain credentials.
type ProviderError struct {
	ProviderID string
	Operation  string
	Kind       ErrorKind
	RetryAfter time.Duration
	Err        error
}

func (e *ProviderError) Error() string {
	if e == nil {
		return ""
	}
	if e.Err == nil {
		return fmt.Sprintf("%s %s: %s", e.ProviderID, e.Operation, e.Kind)
	}
	return fmt.Sprintf("%s %s: %s: %v", e.ProviderID, e.Operation, e.Kind, e.Err)
}

func (e *ProviderError) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Err
}
