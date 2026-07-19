# 本脚本从任意工作目录通过 Air 启动可热重载的 Windows 本地开发服务器。
$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path -Parent $PSScriptRoot
$AirConfigPath = Join-Path $ProjectDir '.air.toml'
$AirVersion = 'v1.62.0'

Push-Location $ProjectDir
try {
    # 优先使用已安装的 Air，避免每次启动都经过 go run 的工具解析过程。
    $AirCommand = Get-Command air -ErrorAction SilentlyContinue
    if ($null -ne $AirCommand) {
        # Windows 不支持 Air 的中断信号；禁用后直接终止进程树，避免 exe 文件锁残留。
        & $AirCommand.Source -c $AirConfigPath '-build.send_interrupt' false '-build.kill_delay' 0 -- @args
    }
    else {
        # 未安装 Air 时使用与 Go 1.24 兼容的固定版本，并由 Go 构建缓存复用工具产物。
        Write-Host "未检测到 Air，正在通过 go run 使用 Air $AirVersion。"
        & go run "github.com/air-verse/air@$AirVersion" -c $AirConfigPath '-build.send_interrupt' false '-build.kill_delay' 0 -- @args
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
