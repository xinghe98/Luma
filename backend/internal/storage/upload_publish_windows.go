//go:build windows

// 本文件提供 Windows 上传的原子不覆盖发布；暂存文件与目标都绑定同一目录句柄。
package storage

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"unsafe"

	"golang.org/x/sys/windows"
)

// uploadRenameInfo 对应 FILE_RENAME_INFORMATION；Flags 为零保证目标存在时拒绝覆盖。
type uploadRenameInfo struct {
	Flags          uint32
	RootDirectory  windows.Handle
	FileNameLength uint32
	FileName       [1]uint16
}

// publishByRename 在硬链接不可用时通过文件句柄重命名，不重新解析来源绝对路径。
func (f *LocalFactory) publishByRename(root *os.Root, stage, name, stem, extension string, base UploadWriteResult) (*UploadWriteResult, error) {
	directory, err := root.Open(".")
	if err != nil {
		return nil, err
	}
	defer directory.Close()
	objectName, err := windows.NewNTUnicodeString(stage)
	if err != nil {
		return nil, err
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
		windows.FILE_OPEN, windows.FILE_NON_DIRECTORY_FILE|windows.FILE_SYNCHRONOUS_IO_NONALERT, 0, 0)
	if err != nil {
		return nil, uploadWindowsError(err)
	}
	defer windows.CloseHandle(handle)
	for i := range 256 {
		candidate := name
		if i > 0 {
			candidate = fmt.Sprintf("%s (%d)%s", stem, i+1, extension)
		}
		encoded, err := windows.UTF16FromString(candidate)
		if err != nil {
			return nil, err
		}
		encoded = encoded[:len(encoded)-1]
		var layout uploadRenameInfo
		buffer := make([]byte, int(unsafe.Offsetof(layout.FileName))+len(encoded)*2)
		info := (*uploadRenameInfo)(unsafe.Pointer(&buffer[0]))
		info.RootDirectory = windows.Handle(directory.Fd())
		info.FileNameLength = uint32(len(encoded) * 2)
		copy(unsafe.Slice(&info.FileName[0], len(encoded)), encoded)
		err = windows.NtSetInformationFile(handle, &status, &buffer[0], uint32(len(buffer)), windows.FileRenameInformation)
		if err == nil {
			result := base
			result.Filename = candidate
			result.RelativePath = filepath.ToSlash(candidate)
			return &result, nil
		}
		err = uploadWindowsError(err)
		if errors.Is(err, windows.ERROR_ALREADY_EXISTS) || errors.Is(err, windows.ERROR_FILE_EXISTS) {
			continue
		}
		return nil, fmt.Errorf("发布上传文件: %w", err)
	}
	return nil, fmt.Errorf("无法为上传文件选择安全名称")
}

// uploadWindowsError 将 NT 状态转换为现有权限和同名冲突判断使用的系统错误。
func uploadWindowsError(err error) error {
	var status windows.NTStatus
	if errors.As(err, &status) {
		return status.Errno()
	}
	return err
}
