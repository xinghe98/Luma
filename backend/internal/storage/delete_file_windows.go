//go:build windows

// 本文件提供 Windows 平台的媒体文件解除目录项实现：相对父目录句柄用
// NtCreateFile 以 FILE_NON_DIRECTORY_FILE|OBJ_DONT_REPARSE 打开目标，
// 目录与链接类对象在打开阶段即被内核拒绝；再以 FILE_DELETE_ON_CLOSE
// 标记删除，关闭句柄时删除已绑定的对象，检查与删除之间不存在
// 目标被换成目录仍可误删的窗口。
package storage

import (
	"errors"
	"os"
	"unsafe"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"golang.org/x/sys/windows"
)

// removeRegularFile 相对父目录句柄原子删除普通文件。
// 与上传发布同一套安全边界：OBJ_DONT_REPARSE 拒绝 Reparse Point，
// FILE_NON_DIRECTORY_FILE 让目录目标在打开阶段失败；
// FILE_DELETE_ON_CLOSE 使删除作用于已打开的同一对象而非路径名，
// 目标在检查后被换成目录也不会误删。
// NT 状态码沿用 uploadWindowsError 转换，保持与上传一致的错误语义。
func removeRegularFile(parent *os.Root, name string) error {
	directory, err := parent.Open(".")
	if err != nil {
		return err
	}
	defer directory.Close()
	objectName, err := windows.NewNTUnicodeString(name)
	if err != nil {
		return err
	}
	attributes := windows.OBJECT_ATTRIBUTES{
		RootDirectory: windows.Handle(directory.Fd()),
		ObjectName:    objectName,
		Attributes:    windows.OBJ_DONT_REPARSE,
	}
	attributes.Length = uint32(unsafe.Sizeof(attributes))
	var handle windows.Handle
	var status windows.IO_STATUS_BLOCK
	err = windows.NtCreateFile(&handle, windows.DELETE|windows.SYNCHRONIZE, &attributes, &status,
		nil, 0, windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE|windows.FILE_SHARE_DELETE,
		windows.FILE_OPEN, windows.FILE_NON_DIRECTORY_FILE|windows.FILE_DELETE_ON_CLOSE|windows.FILE_SYNCHRONOUS_IO_NONALERT, 0, 0)
	if err != nil {
		err = uploadWindowsError(err)
		if errors.Is(err, windows.ERROR_SHARING_VIOLATION) || errors.Is(err, windows.ERROR_LOCK_VIOLATION) {
			return domain.ErrMediaInUse
		}
		return err
	}
	return windows.CloseHandle(handle)
}
