package app

import (
	"errors"
	"reflect"
	"testing"
)

// TestCleanupStackClosesInReverseOrderOnce 验证资源只按逆序清理一次。
func TestCleanupStackClosesInReverseOrderOnce(t *testing.T) {
	var order []string
	stack := &cleanupStack{}
	stack.Push("first", func() error {
		order = append(order, "first")
		return nil
	})
	stack.Push("second", func() error {
		order = append(order, "second")
		return nil
	})
	if err := stack.Close(); err != nil {
		t.Fatal(err)
	}
	if err := stack.Close(); err != nil {
		t.Fatal(err)
	}
	if want := []string{"second", "first"}; !reflect.DeepEqual(order, want) {
		t.Fatalf("cleanup order = %v, want %v", order, want)
	}
}

// TestCleanupStackPreservesResourceContext 验证清理错误包含资源名称。
func TestCleanupStackPreservesResourceContext(t *testing.T) {
	want := errors.New("close failed")
	stack := &cleanupStack{}
	stack.Push("database", func() error { return want })
	err := stack.Close()
	if !errors.Is(err, want) || err.Error() != "close database: close failed" {
		t.Fatalf("unexpected cleanup error: %v", err)
	}
}
