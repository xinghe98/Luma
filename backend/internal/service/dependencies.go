package service

import "time"

// IDGenerator 定义业务服务生成稳定随机标识所需的能力。
type IDGenerator interface {
	// New 使用指定前缀生成新业务标识。
	New(string) (string, error)
}

// Clock 定义业务服务读取当前时间所需的能力。
type Clock interface {
	// Now 返回当前 UTC 时间。
	Now() time.Time
}

// JobNotifier 定义新扫描任务创建后的非阻塞唤醒能力。
type JobNotifier interface {
	// Notify 通知后台 Worker 尽快检查持久化任务队列。
	Notify()
}

// ThumbnailReader 定义媒体服务所需的受控缩略图读取能力。
type ThumbnailReader interface {
	Read(string) ([]byte, error)
}
