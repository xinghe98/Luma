package domain

import "time"

// Tag 表示用户私有标签。
type Tag struct {
	ID             string
	UserID         string
	Name           string
	NormalizedName string
	UsageCount     int64
	Revision       int64
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

// CreateTagCommand 表示创建标签所需数据。
type CreateTagCommand struct {
	UserID string
	Name   string
}

// UpdateTagCommand 表示重命名标签所需数据。
type UpdateTagCommand struct {
	UserID       string
	ID           string
	Name         string
	BaseRevision int64
}
