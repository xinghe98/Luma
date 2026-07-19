# 本脚本以幂等方式安装或更新 Luma Windows 服务，不修改数据目录权限。
param(
    [string]$ServiceName = 'LumaServer',
    [string]$ConfigPath = 'C:\ProgramData\Luma\config.yaml'
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$BinaryPath = Join-Path $ProjectDir 'dist\luma-server.exe'
if (-not (Test-Path -LiteralPath $BinaryPath)) {
    throw "Server binary not found at $BinaryPath. Run scripts\build.ps1 first."
}
$ResolvedBinary = (Resolve-Path -LiteralPath $BinaryPath).Path
$CommandLine = ('"{0}" -config "{1}" -service-name "{2}"' -f $ResolvedBinary, $ConfigPath, $ServiceName)

& sc.exe query $ServiceName *> $null
if ($LASTEXITCODE -eq 0) {
    & sc.exe config $ServiceName binPath= $CommandLine start= auto
}
else {
    & sc.exe create $ServiceName binPath= $CommandLine start= auto DisplayName= 'Luma Media Server'
}
if ($LASTEXITCODE -ne 0) { throw "Failed to install service $ServiceName" }
Write-Host "Installed $ServiceName. Data and configuration are preserved by uninstall."
