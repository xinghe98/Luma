# 本脚本仅卸载 Luma Windows 服务，默认保留配置、数据库和媒体数据。
param([string]$ServiceName = 'LumaServer')

$ErrorActionPreference = 'Stop'
$Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -eq $Service) {
    Write-Host "Service $ServiceName is not installed."
    exit 0
}
if ($Service.Status -ne 'Stopped') {
    Stop-Service -Name $ServiceName -Force
    $Service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
}
& sc.exe delete $ServiceName
if ($LASTEXITCODE -ne 0) { throw "Failed to remove service $ServiceName" }
Write-Host "Removed $ServiceName. Configuration, database, thumbnails, and media were not deleted."
