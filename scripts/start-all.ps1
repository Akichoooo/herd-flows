# 一键拉起 herd-flows 全套生态
# 用法: powershell scripts\start-all.ps1
$ErrorActionPreference = "Stop"
$RootDir = Split-Path $PSScriptRoot -Parent

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       herd-flows 一键启动与自检           " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. 启动网关池
Write-Host "`n[1/3] 启动 Cockpit 反代网关池 ..." -ForegroundColor Cyan
powershell -File (Join-Path $PSScriptRoot "start-proxy.ps1")

# 2. 确保 Herdr 会话在后台运行
Write-Host "`n[2/3] 确保 Herdr 牧场后台会话 ..." -ForegroundColor Cyan
$CfgPath = Join-Path $RootDir "runner\config.json"
$Cfg = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Session = if ($Cfg.herdrSession) { $Cfg.herdrSession } else { "subclaw" }
. (Join-Path $RootDir "orchestrator\adapters\herdr-adapter.ps1")
$HerdrExe = Find-HerdrExe -ExplicitPath $Cfg.PSObject.Properties['herdrExe'].Value

$alive = Test-HerdrSessionAlive -HerdrExe $HerdrExe -Session $Session
if (-not $alive) {
    Write-Host "[start] 正在拉起 Herdr 会话 '$Session' ..." -ForegroundColor Yellow
    Start-Process -WindowStyle Hidden $HerdrExe -ArgumentList "--session", $Session
    Start-Sleep -Seconds 2
} else {
    Write-Host "[ok] Herdr 会话 '$Session' 已在运行" -ForegroundColor Green
}

# 3. 运行 Ensure 自检
Write-Host "`n[3/3] 运行编排引擎 Ensure 自检 ..." -ForegroundColor Cyan
powershell -File (Join-Path $RootDir "runner\herdr-pool.ps1") -Ensure

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "  全套生态已就绪！" -ForegroundColor Green
Write-Host "  - 派发任务: powershell runner\herdr-pool.ps1 -Dispatch `<task`>" -ForegroundColor Green
Write-Host "  - 查看牧场: powershell scripts\start-herdr.ps1" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
