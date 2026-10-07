# 统一构建 TV、Android 和 Windows 发行包；复用 Flutter、应用元数据与 NSIS，顺序构建并将验证后的产物收集到 build/dist。
#requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('p')]
    [ValidateSet('tv', 'android', 'win')]
    [string]$Platform
)

$ErrorActionPreference = 'Stop'
$MobileDir = Split-Path -Parent $PSScriptRoot
$OutputDir = Join-Path $MobileDir 'build/dist'
$Platforms = if ($Platform) { @($Platform) } else { @('tv', 'android', 'win') }

# 执行 Flutter 并保留日志；失败时停止后续平台，避免收集上一次构建的产物。
function Invoke-Flutter {
    param([string[]]$Arguments)

    & flutter @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter 执行失败（退出码 $LASTEXITCODE）：flutter $($Arguments -join ' ')"
    }
}

# 校验 APK 的准确 ABI 集合及每个架构必需的原生库，拒绝缺库或混入模拟器架构的发行包。
function Assert-ApkLibraries {
    param([string]$Path, [string[]]$ExpectedAbis)

    # Windows PowerShell 5.1 不会自动加载 ZIP API 所在的程序集。
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $Libraries = @{}
        foreach ($Entry in $Archive.Entries) {
            if ($Entry.FullName -match '^lib/([^/]+)/([^/]+)$') {
                if (-not $Libraries.ContainsKey($Matches[1])) {
                    $Libraries[$Matches[1]] = [System.Collections.Generic.HashSet[string]]::new()
                }
                [void]$Libraries[$Matches[1]].Add($Matches[2])
            }
        }
        $ActualAbis = @($Libraries.Keys | Sort-Object)
        if (($ActualAbis -join ',') -ne (($ExpectedAbis | Sort-Object) -join ',')) {
            throw "APK 架构不匹配：期望 $($ExpectedAbis -join ', ')，实际 $($ActualAbis -join ', ')。"
        }
        foreach ($Abi in $ExpectedAbis) {
            foreach ($Library in @('libflutter.so', 'libapp.so', 'libmpv.so', 'libgojni.so')) {
                if (-not $Libraries[$Abi].Contains($Library)) {
                    throw "APK 缺少 lib/$Abi/$Library。"
                }
            }
        }
    }
    finally {
        $Archive.Dispose()
    }
}

# 构建指定 Android 形态；按本次 Gradle 输出收集 APK，未签名包保留明确后缀。
function New-AndroidPackage {
    param([ValidateSet('tv', 'android')][string]$Target)

    $ReleaseDir = Join-Path $MobileDir 'build/app/outputs/apk/release'
    if (Test-Path -LiteralPath $ReleaseDir) {
        Get-ChildItem -LiteralPath $ReleaseDir -File -Filter '*.apk' | Remove-Item -Force
    }
    $IsTv = $Target -eq 'tv'
    $TargetPlatform = if ($IsTv) { 'android-arm,android-arm64' } else { 'android-arm64' }
    $AbiSelection = if ($IsTv) { 'arm' } else { 'arm64' }
    $TvDefine = if ($IsTv) { 'true' } else { 'false' }
    Invoke-Flutter -Arguments @(
        'build', 'apk', '--release', '--target-platform', $TargetPlatform,
        "--dart-define=LUMA_TV=$TvDefine", "--android-project-arg=lumaTvAbis=$AbiSelection"
    )

    $Apks = @(Get-ChildItem -LiteralPath $ReleaseDir -File -Filter '*.apk')
    if ($Apks.Count -ne 1) {
        throw "本次 $Target 构建应生成一个 APK，实际为 $($Apks.Count) 个。"
    }
    $ExpectedAbis = if ($IsTv) { @('armeabi-v7a', 'arm64-v8a') } else { @('arm64-v8a') }
    Assert-ApkLibraries -Path $Apks[0].FullName -ExpectedAbis $ExpectedAbis
    $Unsigned = $Apks[0].BaseName.EndsWith('-unsigned')
    $Suffix = if ($Unsigned) { '-unsigned' } else { '' }
    $PackagePlatform = if ($IsTv) { 'android-tv-armv7-arm64' } else { 'android-arm64-v8a' }
    $PackagePath = Join-Path $OutputDir "$($Metadata.projectName)-$ClientVersion-$PackagePlatform$Suffix.apk"
    Copy-Item -LiteralPath $Apks[0].FullName -Destination $PackagePath -Force
    if ($Unsigned) {
        Write-Warning "$Target APK 未签名，不能作为可安装发行包；请配置 android/key.properties 后重新打包。"
    }
    return $PackagePath
}

# 优先从 PATH 解析 NSIS，再查找标准安装目录；缺失时不开始 Windows 构建。
function Get-MakensisPath {
    $Command = Get-Command makensis -ErrorAction SilentlyContinue
    if ($null -ne $Command) { return $Command.Source }
    foreach ($Root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $Root) { continue }
        $Candidate = Join-Path $Root 'NSIS/makensis.exe'
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) { return $Candidate }
    }
    throw '找不到 makensis，请安装 NSIS 3 并加入 PATH。'
}

# 定位 Visual Studio 的最新 x64 CRT，安装包采用应用目录内运行库，无需另装 VC++ 安装程序。
function Get-VisualCppRuntime {
    $Vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $Vswhere -PathType Leaf)) {
        throw '找不到 vswhere，请安装 Visual Studio C++ 桌面开发工具链。'
    }
    $Installation = & $Vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Installation)) {
        throw '找不到包含 C++ 工具链的 Visual Studio。'
    }
    $RedistRoot = Join-Path $Installation.Trim() 'VC/Redist/MSVC'
    $Version = Get-ChildItem -LiteralPath $RedistRoot -Directory |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $Version) { throw '找不到 Visual C++ 运行库版本目录。' }
    $Runtime = Get-ChildItem -LiteralPath (Join-Path $Version.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
        Select-Object -First 1
    if ($null -eq $Runtime) { throw '找不到 x64 Visual C++ 运行库。' }
    return $Runtime.FullName
}

# 转义 NSIS 字符串，避免元数据或工作区路径中的美元符号被当成安装器变量。
function ConvertTo-NsisLiteral {
    param([string]$Value)

    return $Value.Replace('$', '$$').Replace('"', '$\"')
}

# 构建并组装 Windows x64 安装包；临时目录始终清理，成功后才替换 dist 中的同版本安装包。
function New-WindowsPackage {
    Invoke-Flutter -Arguments @('build', 'windows', '--release')
    $BuildDir = Join-Path $MobileDir 'build/windows/x64/runner/Release'
    $WorkDir = Join-Path $OutputDir ('.package-windows-' + [Guid]::NewGuid().ToString('N'))
    $StageDir = Join-Path $WorkDir 'stage'
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
    try {
        Copy-Item -Path (Join-Path $BuildDir '*') -Destination $StageDir -Recurse
        Copy-Item -LiteralPath (Join-Path $MobileDir 'windows/WINDOWS-README.txt') -Destination $StageDir
        Copy-Item -LiteralPath (Join-Path $MobileDir 'assets/fonts/MiSans-LICENSE.pdf') -Destination $StageDir
        $AppIcon = Join-Path $MobileDir 'windows/runner/resources/app_icon.ico'
        Copy-Item -LiteralPath $AppIcon -Destination (Join-Path $StageDir 'luma.ico')
        Copy-Item -Path (Join-Path $VisualCppRuntime '*.dll') -Destination $StageDir

        $ExeName = "$($Metadata.windowsExecutableName).exe"
        foreach ($RequiredFile in @(
            $ExeName, 'flutter_windows.dll', 'libmpv-2.dll', 'libXray.dll',
            'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
            'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z',
            'data/flutter_assets/assets/licenses/libXray-MIT.txt',
            'data/flutter_assets/assets/licenses/Xray-core-MPL-2.0.txt',
            'WINDOWS-README.txt', 'MiSans-LICENSE.pdf', 'luma.ico'
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $StageDir $RequiredFile) -PathType Leaf)) {
                throw "Windows 发行目录缺少 $RequiredFile。"
            }
        }

        $InstallerName = "$($Metadata.projectName)-$ClientVersion-windows-x64-setup.exe"
        $TemporaryInstaller = Join-Path $WorkDir $InstallerName
        $VersionMatch = [regex]::Match($ClientVersion, '^(\d+)\.(\d+)\.(\d+)')
        $VersionQuad = "$($VersionMatch.Groups[1].Value).$($VersionMatch.Groups[2].Value).$($VersionMatch.Groups[3].Value).0"
        $Definitions = [ordered]@{
            PRODUCT_NAME = $Metadata.productName
            PRODUCT_VERSION = $ClientVersion
            PRODUCT_VERSION_QUAD = $VersionQuad
            COMPANY_NAME = $Metadata.companyName
            COPYRIGHT = $Metadata.copyright
            INSTALL_DIR_NAME = $Metadata.productName
            PRODUCT_REG_KEY = $Metadata.projectName
            EXE_NAME = $ExeName
            INSTALLER_FILE_NAME = $InstallerName
            STAGE_DIR = $StageDir.Replace('\', '/')
            OUT_FILE = $TemporaryInstaller.Replace('\', '/')
            APP_ICON = $AppIcon.Replace('\', '/')
        }
        $Defines = foreach ($Entry in $Definitions.GetEnumerator()) {
            '!define {0} "{1}"' -f $Entry.Key, (ConvertTo-NsisLiteral -Value $Entry.Value)
        }
        $Utf8Bom = [System.Text.UTF8Encoding]::new($true)
        $NsiFile = Join-Path $WorkDir 'luma.nsi'
        [System.IO.File]::WriteAllText(
            $NsiFile, [System.IO.File]::ReadAllText((Join-Path $MobileDir 'windows/installer/luma.nsi')), $Utf8Bom
        )
        [System.IO.File]::WriteAllText((Join-Path $WorkDir 'installer-defines.nsh'), ($Defines -join "`r`n") + "`r`n", $Utf8Bom)
        & $Makensis /V2 $NsiFile | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "NSIS 编译失败，退出码：$LASTEXITCODE" }
        if (-not (Test-Path -LiteralPath $TemporaryInstaller -PathType Leaf)) {
            throw 'NSIS 未生成安装包。'
        }
        $PackagePath = Join-Path $OutputDir $InstallerName
        Move-Item -LiteralPath $TemporaryInstaller -Destination $PackagePath -Force
        return $PackagePath
    }
    finally {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force
    }
}

if ('win' -in $Platforms -and [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows 安装包必须在 Windows 主机构建；当前主机请使用 -p tv 或 -p android。'
}
Get-Command flutter -ErrorAction Stop | Out-Null
Get-Command dart -ErrorAction Stop | Out-Null
if ('win' -in $Platforms) {
    $Makensis = Get-MakensisPath
    $VisualCppRuntime = Get-VisualCppRuntime
}

Push-Location $MobileDir
try {
    & dart run tool/sync_app_metadata.dart --check | Out-Host
    if ($LASTEXITCODE -ne 0) { throw '应用元数据未同步，请执行 dart run tool/sync_app_metadata.dart。' }
    $Metadata = Get-Content -LiteralPath (Join-Path $MobileDir 'app_metadata.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $ClientVersion = $Metadata.version.Split('+')[0]
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $Packages = foreach ($Target in $Platforms) {
        Write-Host "正在打包 $Target（$ClientVersion）……"
        if ($Target -eq 'win') { New-WindowsPackage } else { New-AndroidPackage -Target $Target }
    }
    Write-Host '打包完成，产物：'
    $Packages | Write-Output
}
finally {
    Pop-Location
}
