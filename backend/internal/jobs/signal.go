package jobs

// Signal 使用容量为一的通道合并重复任务唤醒通知。
type Signal struct {
	// channel 保存待消费的唤醒信号。
	channel chan struct{}
}

// NewSignal 创建非阻塞任务唤醒器。
func NewSignal() *Signal {
	return &Signal{channel: make(chan struct{}, 1)}
}

// Notify 非阻塞发送唤醒信号，已有信号时自动合并。
func (s *Signal) Notify() {
	select {
	case s.channel <- struct{}{}:
	default:
	}
}

// C 返回只读通知通道供 Worker 等待。
func (s *Signal) C() <-chan struct{} {
	return s.channel
}
