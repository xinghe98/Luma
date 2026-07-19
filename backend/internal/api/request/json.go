package request

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
)

// maxJSONBodyBytes 是普通 JSON API 接受的最大请求体字节数。
const maxJSONBodyBytes int64 = 1 << 20

// DecodeJSON 严格解码单个 JSON 对象，并拒绝未知字段和超限请求体。
func DecodeJSON(c *gin.Context, target any) error {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxJSONBodyBytes)
	decoder := json.NewDecoder(c.Request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("JSON 请求体无效: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("JSON 请求体只能包含一个对象")
	}
	return nil
}
