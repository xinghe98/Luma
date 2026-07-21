# 本脚本构建带版本信息的 Windows 服务端二进制。
param([string]$Version = 'dev')

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$DistDir = Join-Path $ProjectDir 'dist'
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Push-Location $ProjectDir
$PreviousCGOEnabled = $env:CGO_ENABLED
try {
    $env:CGO_ENABLED = '0'
    & go build -trimpath -ldflags "-s -w -X main.version=$Version" -o (Join-Path $DistDir 'luma-server.exe') ./cmd/server
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    $env:CGO_ENABLED = $PreviousCGOEnabled
    Pop-Location
}
