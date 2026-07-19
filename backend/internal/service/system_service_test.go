package service

import (
	"context"
	"errors"
	"testing"
)

// fakePinger 为系统服务测试提供可控的数据库连通性结果。
type fakePinger struct {
	// err 是 PingContext 返回的预设错误。
	err error
}

// PingContext 返回预设的数据库检查结果。
func (p fakePinger) PingContext(context.Context) error { return p.err }

// TestSystemServiceUsesInjectedDatabase 验证系统服务使用注入的数据库接口。
func TestSystemServiceUsesInjectedDatabase(t *testing.T) {
	service, err := NewSystemService("test-version", fakePinger{})
	if err != nil {
		t.Fatal(err)
	}
	info, err := service.Info(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if info.Version != "test-version" || info.Database != "ok" {
		t.Fatalf("unexpected info: %#v", info)
	}
}

// TestSystemServicePropagatesInjectedDatabaseFailure 验证数据库错误会向上返回。
func TestSystemServicePropagatesInjectedDatabaseFailure(t *testing.T) {
	want := errors.New("database unavailable")
	service, err := NewSystemService("test-version", fakePinger{err: want})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Info(context.Background()); !errors.Is(err, want) {
		t.Fatalf("error = %v, want %v", err, want)
	}
}
