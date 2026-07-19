# 本脚本仅卸载 Luma Windows 服务，默认保留配置、数据库和媒体数据。
param([string]$ServiceName = 'LumaServer')

$ErrorActionPreference = 'Stop'
& sc.exe query $ServiceName *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Service $ServiceName is not installed."
    exit 0
}
& sc.exe stop $ServiceName *> $null
& sc.exe delete $ServiceName
if ($LASTEXITCODE -ne 0) { throw "Failed to remove service $ServiceName" }
Write-Host "Removed $ServiceName. Configuration, database, thumbnails, and media were not deleted."
