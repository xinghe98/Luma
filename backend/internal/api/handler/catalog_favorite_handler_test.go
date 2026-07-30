// 作品收藏接口测试验证当前用户、乐观并发版本和响应字段不会退化为媒体级收藏。
package handler

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestCatalogHandlerUpdateFavorite(t *testing.T) {
	gin.SetMode(gin.TestMode)
	service := &catalogFavoriteHandlerService{}
	handler, err := NewCatalogHandler(service)
	if err != nil {
		t.Fatal(err)
	}
	engine := gin.New()
	engine.Use(func(c *gin.Context) { c.Set("user_id", "user_local") })
	engine.PATCH("/catalog/:id/user-data", handler.UpdateFavorite)
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPatch, "/catalog/catalog_1/user-data",
		strings.NewReader(`{"favorite":true,"base_revision":4}`))
	request.Header.Set("Content-Type", "application/json")
	engine.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if service.itemID != "catalog_1" || service.userID != "user_local" || !service.favorite || service.revision != 4 {
		t.Fatalf("request=%#v", service)
	}
	if !strings.Contains(recorder.Body.String(), `"favorite":true`) ||
		!strings.Contains(recorder.Body.String(), `"revision":5`) {
		t.Fatalf("body=%s", recorder.Body.String())
	}
}

type catalogFavoriteHandlerService struct {
	itemID   string
	userID   string
	favorite bool
	revision int64
}

func (s *catalogFavoriteHandlerService) List(context.Context, domain.CatalogListRequest, string) ([]domain.CatalogItem, error) {
	return nil, nil
}

func (s *catalogFavoriteHandlerService) Get(context.Context, string, string) (domain.CatalogItem, error) {
	return domain.CatalogItem{}, nil
}

// UpdateFavorite 记录 Handler 传入的作品收藏请求并返回新的版本号。
func (s *catalogFavoriteHandlerService) UpdateFavorite(_ context.Context, itemID, userID string, favorite bool, revision int64) (domain.CatalogUserData, error) {
	s.itemID, s.userID, s.favorite, s.revision = itemID, userID, favorite, revision
	return domain.CatalogUserData{CatalogItemID: itemID, Favorite: favorite, Revision: revision + 1,
		UpdatedAt: time.Date(2026, 7, 25, 0, 0, 0, 0, time.UTC)}, nil
}
