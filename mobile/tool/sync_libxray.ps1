[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Version = 'v26.7.28'
$ReleaseBase = "https://github.com/XTLS/libXray/releases/download/$Version"

function Get-FileSha256([string] $Path) {
    $Stream = [System.IO.File]::OpenRead($Path)
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString(
            $Hasher.ComputeHash($Stream)
        ).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $Hasher.Dispose()
        $Stream.Dispose()
    }
}
$Artifacts = @(
    @{
        Name = 'libxray-android.zip'
        Sha256 = '28b7dc9d6cc8455fcca5cbd56e387003a7bfb558128651a64899dc3a8ccff666'
        FileName = 'libXray.aar'
        Destination = 'android/app/libs/libXray.aar'
    },
    @{
        Name = 'libxray-windows-x64.zip'
        Sha256 = '0b270147c73448b4db6a050767c37cb217ba64459fa19e5e61f08fe3c2bdaafc'
        FileName = 'libXray.dll'
        Destination = 'windows/libxray/libXray.dll'
    }
)
$Licenses = @(
    @{
        Name = 'libXray'
        Uri = "https://raw.githubusercontent.com/XTLS/libXray/$Version/LICENSE"
        Sha256 = '992cf88a505936a11bd0fff17b7842abd9411e8da41fd69f22f47ae915e9d198'
        Destination = 'assets/licenses/libXray-MIT.txt'
    },
    @{
        Name = 'Xray-core'
        Uri = "https://raw.githubusercontent.com/XTLS/Xray-core/$Version/LICENSE"
        Sha256 = '1f256ecad192880510e84ad60474eab7589218784b9a50bc7ceee34c2b91f1d5'
        Destination = 'assets/licenses/Xray-core-MPL-2.0.txt'
    }
)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("luma-libxray-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot | Out-Null

try {
    foreach ($Artifact in $Artifacts) {
        $ArchivePath = Join-Path $TempRoot $Artifact.Name
        $ExtractPath = Join-Path $TempRoot ([System.IO.Path]::GetFileNameWithoutExtension($Artifact.Name))
        Invoke-WebRequest -Uri "$ReleaseBase/$($Artifact.Name)" -OutFile $ArchivePath

        $ActualHash = Get-FileSha256 $ArchivePath
        if ($ActualHash -ne $Artifact.Sha256) {
            throw "libXray 摘要不匹配：$($Artifact.Name)，期望 $($Artifact.Sha256)，实际 $ActualHash。"
        }

        Expand-Archive -Path $ArchivePath -DestinationPath $ExtractPath -Force
        $Candidates = @(Get-ChildItem -Path $ExtractPath -Recurse -File -Filter $Artifact.FileName)
        if ($Candidates.Count -ne 1) {
            throw "libXray 压缩包结构无效：$($Artifact.Name) 中找到 $($Candidates.Count) 个 $($Artifact.FileName)。"
        }

        $DestinationPath = Join-Path $ProjectRoot $Artifact.Destination
        $DestinationDirectory = Split-Path -Parent $DestinationPath
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
        $StagedPath = "$DestinationPath.new"
        Copy-Item -Path $Candidates[0].FullName -Destination $StagedPath -Force
        Move-Item -Path $StagedPath -Destination $DestinationPath -Force
        Write-Host "已同步 $($Artifact.Destination) ($Version)"
    }

    foreach ($License in $Licenses) {
        $LicensePath = Join-Path $TempRoot ($License.Name + '.LICENSE')
        Invoke-WebRequest -Uri $License.Uri -OutFile $LicensePath
        $ActualHash = Get-FileSha256 $LicensePath
        if ($ActualHash -ne $License.Sha256) {
            throw "许可文本摘要不匹配：$($License.Name)，期望 $($License.Sha256)，实际 $ActualHash。"
        }

        $DestinationPath = Join-Path $ProjectRoot $License.Destination
        $DestinationDirectory = Split-Path -Parent $DestinationPath
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
        $StagedPath = "$DestinationPath.new"
        Copy-Item -Path $LicensePath -Destination $StagedPath -Force
        Move-Item -Path $StagedPath -Destination $DestinationPath -Force
        Write-Host "已同步 $($License.Destination) ($Version)"
    }
}
finally {
    Remove-Item -Path $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
