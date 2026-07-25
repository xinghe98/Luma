// Package nfo implements the read-only Kodi/Jellyfin sidecar metadata provider.
// Luma owns path validation and supplies an already opened reader to this parser.
package nfo

import (
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

const maxNFOBytes = 2 << 20

// Provider parses local NFO sidecars without opening or writing media paths.
type Provider struct{}

var _ scraper.SidecarParser = Provider{}

// New creates the stateless NFO provider.
func New() Provider { return Provider{} }

// Descriptor declares the NFO sidecar capability for movies and series.
func (Provider) Descriptor() scraper.Descriptor {
	return scraper.Descriptor{
		ID: "nfo", Name: "Local NFO",
		Kinds:        []scraper.MediaKind{scraper.MediaKindMovie, scraper.MediaKindSeries},
		Capabilities: []scraper.Capability{scraper.CapabilitySidecar},
	}
}

type uniqueID struct {
	Type  string `xml:"type,attr"`
	Value string `xml:",chardata"`
}

type document struct {
	Title         string     `xml:"title"`
	OriginalTitle string     `xml:"originaltitle"`
	Plot          string     `xml:"plot"`
	Tagline       string     `xml:"tagline"`
	Premiered     string     `xml:"premiered"`
	ReleaseDate   string     `xml:"releasedate"`
	Year          string     `xml:"year"`
	Runtime       string     `xml:"runtime"`
	MPAA          string     `xml:"mpaa"`
	Rating        string     `xml:"rating"`
	Genres        []string   `xml:"genre"`
	TMDbID        string     `xml:"tmdbid"`
	IMDbID        string     `xml:"imdbid"`
	TVDbID        string     `xml:"tvdbid"`
	UniqueIDs     []uniqueID `xml:"uniqueid"`
}

// ParseSidecar decodes a bounded XML document into a partial normalized patch.
func (Provider) ParseSidecar(ctx context.Context, request scraper.SidecarRequest) (scraper.MetadataPatch, error) {
	if request.Body == nil {
		return scraper.MetadataPatch{}, errors.New("NFO reader is required")
	}
	if err := ctx.Err(); err != nil {
		return scraper.MetadataPatch{}, err
	}
	decoder := xml.NewDecoder(io.LimitReader(request.Body, maxNFOBytes+1))
	decoder.Strict = true
	var value document
	if err := decoder.Decode(&value); err != nil {
		return scraper.MetadataPatch{}, &scraper.ProviderError{
			ProviderID: "nfo", Operation: "parse", Kind: scraper.ErrorInvalidResponse, Err: err,
		}
	}
	patch := scraper.MetadataPatch{
		Title: stringPointer(value.Title), OriginalTitle: stringPointer(value.OriginalTitle),
		Overview: stringPointer(value.Plot), Tagline: stringPointer(value.Tagline),
		Certification: stringPointer(value.MPAA), ExternalIDs: map[string]string{},
	}
	releaseDate := firstNonEmpty(value.Premiered, value.ReleaseDate)
	patch.ReleaseDate = stringPointer(releaseDate)
	if year, err := strconv.Atoi(strings.TrimSpace(value.Year)); err == nil && year >= 1800 && year <= 3000 {
		patch.Year = &year
	}
	if runtime, err := strconv.Atoi(strings.TrimSpace(value.Runtime)); err == nil && runtime > 0 {
		duration := time.Duration(runtime) * time.Minute
		patch.Runtime = &duration
	}
	if rating, err := strconv.ParseFloat(strings.TrimSpace(value.Rating), 64); err == nil {
		patch.CommunityRating = &rating
	}
	if len(value.Genres) > 0 {
		genres := make([]scraper.NamedValue, 0, len(value.Genres))
		for _, genre := range value.Genres {
			if name := strings.TrimSpace(genre); name != "" {
				genres = append(genres, scraper.NamedValue{Name: name})
			}
		}
		patch.Genres = &genres
	}
	addID(patch.ExternalIDs, "tmdb", value.TMDbID)
	addID(patch.ExternalIDs, "imdb", value.IMDbID)
	addID(patch.ExternalIDs, "tvdb", value.TVDbID)
	for _, id := range value.UniqueIDs {
		addID(patch.ExternalIDs, strings.ToLower(strings.TrimSpace(id.Type)), id.Value)
	}
	if len(patch.ExternalIDs) == 0 {
		patch.ExternalIDs = nil
	}
	return patch, nil
}

func stringPointer(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func addID(target map[string]string, name, value string) {
	name, value = strings.TrimSpace(name), strings.TrimSpace(value)
	if name != "" && value != "" {
		target[name] = value
	}
}

func (Provider) String() string { return fmt.Sprint("nfo") }
