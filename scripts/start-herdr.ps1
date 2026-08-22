# 启动并挂载 Herdr 终端牧场 (TUI)
# 用法: powershell scripts\start-herdr.ps1 [-Background]
param(
    [switch]$Background
)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path $PSScriptRoot -Parent
$CfgPath = Join-Path $RootDir "runner\config.json"
$Cfg = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Session = if ($Cfg.herdrSession) { $Cfg.herdrSession } else { "subclaw" }

. (Join-Path $RootDir "orchestrator\adapters\herdr-adapter.ps1")
$HerdrExe = Find-HerdrExe -ExplicitPath $Cfg.PSObject.Properties['herdrExe'].Value

Write-Host "=== 启动 Herdr 会话 '$Session' ===" -ForegroundColor Cyan

if ($Background) {
    Write-Host "[start] 在后台启动 Herdr 服务..."
    Start-Process -WindowStyle Hidden $HerdrExe -ArgumentList "--session", $Session
    Write-Host "[ok] Herdr 后台会话 '$Session' 已启动！" -ForegroundColor Green
} else {
    Write-Host "[start] 进入 Herdr 终端 TUI 看板 (按 Ctrl+B Q 可退出回退)..." -ForegroundColor Yellow
    & $HerdrExe --session $Session
}
