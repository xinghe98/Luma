package handler

import (
	"bytes"
	"encoding/json"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// optionalJSON 保留 PATCH 字段缺失、null 和具体值三态。
type optionalJSON[T any] struct {
	Set   bool
	Null  bool
	Value T
}

func (value *optionalJSON[T]) UnmarshalJSON(data []byte) error {
	value.Set = true
	if bytes.Equal(bytes.TrimSpace(data), []byte("null")) {
		value.Null = true
		return nil
	}
	return json.Unmarshal(data, &value.Value)
}

func (value optionalJSON[T]) patchField() domain.PatchField[T] {
	result := domain.PatchField[T]{Set: value.Set}
	if value.Set && !value.Null {
		result.Value = &value.Value
	}
	return result
}
