# 本脚本以幂等方式安装或更新 Luma Windows 服务，不修改数据目录权限。
param(
    [string]$ServiceName = 'LumaServer',
    [string]$ConfigPath = 'C:\ProgramData\Luma\config.yaml',
    [string]$InstallDir = 'C:\Program Files\Luma'
)

$ErrorActionPreference = 'Stop'
$Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

$ProjectDir = Split-Path -Parent $PSScriptRoot
$SourceBinary = Join-Path $ProjectDir 'dist\luma-server.exe'
if (-not (Test-Path -LiteralPath $SourceBinary -PathType Leaf)) {
    throw "Server binary not found at $SourceBinary. Run scripts\build.ps1 first."
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration not found at $ConfigPath. Copy and edit configs\config.windows.example.yaml first."
}
$ResolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path

& $SourceBinary -config $ResolvedConfig -check-config -log-format text
if ($LASTEXITCODE -ne 0) { throw 'Configuration or runtime dependency check failed.' }

$ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $ExistingService -and $ExistingService.Status -ne 'Stopped') {
    Stop-Service -Name $ServiceName -Force
    $ExistingService.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$InstalledBinary = Join-Path $InstallDir 'luma-server.exe'
Copy-Item -LiteralPath $SourceBinary -Destination $InstalledBinary -Force
$ResolvedBinary = (Resolve-Path -LiteralPath $InstalledBinary).Path
$CommandLine = ('"{0}" -config "{1}" -service-name "{2}"' -f $ResolvedBinary, $ResolvedConfig, $ServiceName)

if ($null -ne $ExistingService) {
    & sc.exe config $ServiceName binPath= $CommandLine start= auto
}
else {
    & sc.exe create $ServiceName binPath= $CommandLine start= auto DisplayName= 'Luma Media Server'
}
if ($LASTEXITCODE -ne 0) { throw "Failed to install service $ServiceName" }
& sc.exe description $ServiceName 'Luma local media server'
if ($LASTEXITCODE -ne 0) { throw "Failed to set description for service $ServiceName" }
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/15000/restart/30000
if ($LASTEXITCODE -ne 0) { throw "Failed to configure recovery for service $ServiceName" }

Start-Service -Name $ServiceName
(Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
Write-Host "Installed and started $ServiceName from $ResolvedBinary."
Write-Host 'Configuration and data are preserved by uninstall.'
