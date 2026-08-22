# 一键检查并更新 Herdr 与 Cockpit Tools 上游
# 用法: powershell scripts\update-all-upstreams.ps1
$ErrorActionPreference = "Stop"
$RootDir = Split-Path $PSScriptRoot -Parent

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "     herd-flows 上游依赖一键更新检查       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. 更新 Herdr
Write-Host "`n=== [1/2] 检查 Herdr 运行时上游 ===" -ForegroundColor Cyan
. (Join-Path $RootDir "vendor\herdr\update-herdr.ps1")

# 2. 更新 Cockpit Tools
Write-Host "`n=== [2/2] 检查 Cockpit Tools 反代源码上游 ===" -ForegroundColor Cyan
. (Join-Path $RootDir "proxy\update-cockpit.ps1")

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "  上游同步检查完成！" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
