package domain

import "time"

// PatchField 表示 PATCH 字段的缺失、null 或具体值三态。
type PatchField[T any] struct {
	Set   bool
	Value *T
}

// MediaUserData 表示一个用户对媒体保存的可变数据。
type MediaUserData struct {
	UserID       string
	MediaID      string
	CustomTitle  *string
	Favorite     bool
	Notes        *string
	ProgressMS   int64
	Completed    bool
	LastPlayedAt *time.Time
	Tags         []Tag
	Revision     int64
	CreatedAt    *time.Time
	UpdatedAt    *time.Time
}

// UpdateUserDataCommand 表示用户数据与标签的原子 PATCH。
type UpdateUserDataCommand struct {
	UserID       string
	MediaID      string
	BaseRevision int64
	CustomTitle  PatchField[string]
	Favorite     PatchField[bool]
	Notes        PatchField[string]
	TagIDs       PatchField[[]string]
}

// UpdateProgressCommand 表示一次播放进度写入。
// PositionMS 为客户端上报位置；服务端在事务内按媒体时长截断并计算 completed。
type UpdateProgressCommand struct {
	UserID       string
	MediaID      string
	PositionMS   int64
	BaseRevision int64
	Now          time.Time
}
