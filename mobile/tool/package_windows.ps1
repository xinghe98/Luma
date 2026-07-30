# Windows 便携包脚本复制 Flutter Release 产物和使用说明，并在临时目录内完成压缩与清理。
# 依赖 flutter build windows 的标准目录结构；所有递归操作都限制在项目 build\dist 下。
param(
  [string]$Version = "",
  [string]$BuildDirectory = "build\windows\x64\runner\Release",
  [string]$OutputDirectory = "build\dist"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$buildPath = (Resolve-Path -LiteralPath (Join-Path $projectRoot $BuildDirectory)).Path
if (-not $buildPath.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Windows 构建目录不在项目内：$buildPath"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $pubspec = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "pubspec.yaml")
  $match = [regex]::Match($pubspec, "(?m)^version:\s*([^\s+]+)")
  if (-not $match.Success) {
    throw "无法从 pubspec.yaml 读取版本号"
  }
  $Version = $match.Groups[1].Value
}

$outputPath = Join-Path $projectRoot $OutputDirectory
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$packageName = "luma-windows-x64-$Version"
$stagePath = Join-Path $outputPath $packageName
if (Test-Path -LiteralPath $stagePath) {
  $resolvedStage = (Resolve-Path -LiteralPath $stagePath).Path
  $resolvedOutput = (Resolve-Path -LiteralPath $outputPath).Path
  if ((Split-Path -Parent $resolvedStage) -ne $resolvedOutput) {
    throw "拒绝清理非预期目录：$resolvedStage"
  }
  Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}

New-Item -ItemType Directory -Path $stagePath | Out-Null
Copy-Item -Path (Join-Path $buildPath "*") -Destination $stagePath -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot "windows\WINDOWS-README.txt") -Destination $stagePath
Copy-Item -LiteralPath (Join-Path $projectRoot "assets\fonts\MiSans-LICENSE.pdf") -Destination $stagePath

$vswherePath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswherePath)) {
  throw "找不到 vswhere，无法收集 Visual C++ 运行库"
}
$vsInstall = (& $vswherePath -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if ([string]::IsNullOrWhiteSpace($vsInstall)) {
  throw "找不到包含 C++ 工具链的 Visual Studio"
}
$redistRoot = Join-Path $vsInstall "VC\Redist\MSVC"
$redistVersion = Get-ChildItem -LiteralPath $redistRoot -Directory |
  Where-Object { $_.Name -match "^\d+(\.\d+)+$" } |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1
$crtDirectory = Get-ChildItem -LiteralPath (Join-Path $redistVersion.FullName "x64") -Directory -Filter "Microsoft.VC*.CRT" |
  Select-Object -First 1
if ($null -eq $crtDirectory) {
  throw "找不到 x64 Visual C++ 运行库"
}
Copy-Item -Path (Join-Path $crtDirectory.FullName "*.dll") -Destination $stagePath

$archivePath = Join-Path $outputPath "$packageName.zip"
Compress-Archive -Path (Join-Path $stagePath "*") -DestinationPath $archivePath -Force
$resolvedStage = (Resolve-Path -LiteralPath $stagePath).Path
if ((Split-Path -Parent $resolvedStage) -ne (Resolve-Path -LiteralPath $outputPath).Path) {
  throw "拒绝清理非预期目录：$resolvedStage"
}
Remove-Item -LiteralPath $resolvedStage -Recurse -Force
Write-Output $archivePath
