# 本脚本在 Windows 上通过 Air 启动后端热重载；它依赖 Go 与 .air.toml，并负责规避热重载产生的 exe 文件锁。
$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$AirConfigPath = Join-Path $ProjectDir '.air.toml'
$AirVersion = 'v1.62.0'

if (-not $IsWindows) {
    throw 'Windows 开发脚本只能在 Windows 上运行。'
}

Push-Location $ProjectDir
try {
    # 优先使用已安装的 Air，避免每次启动都经过 go run 的工具解析过程。
    $AirCommand = Get-Command air -ErrorAction SilentlyContinue
    if ($null -ne $AirCommand) {
        & $AirCommand.Source -c $AirConfigPath '-build.send_interrupt' false '-build.kill_delay' 0 -- @args
    }
    else {
        Write-Host "未检测到 Air，正在通过 go run 使用 Air $AirVersion。"
        & go run "github.com/air-verse/air@$AirVersion" -c $AirConfigPath '-build.send_interrupt' false '-build.kill_delay' 0 -- @args
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
