# 一键构建 Windows x64 NSIS 安装包；实际打包逻辑在 backend/scripts/windows-deploy.ps1。
param(
    [string]$Version = 'dev',
    [string]$ClientBuildDirectory = 'build\windows\x64\runner\Release',
    [string]$ClientOutputDirectory = 'build\dist',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$DeployScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\scripts\windows-deploy.ps1'
if (-not (Test-Path -LiteralPath $DeployScript -PathType Leaf)) {
    throw "找不到打包入口：$DeployScript"
}

& $DeployScript `
    -Action PackageClient `
    -Version $Version `
    -ClientBuildDirectory $ClientBuildDirectory `
    -ClientOutputDirectory $ClientOutputDirectory `
    -SkipBuild:$SkipBuild
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
    exit $LASTEXITCODE
}
