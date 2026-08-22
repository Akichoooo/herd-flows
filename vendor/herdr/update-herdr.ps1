# Herdr 升级脚本
# 用法: powershell vendor\herdr\update-herdr.ps1
$ErrorActionPreference = "Stop"

Write-Host "=== 更新 Herdr 到最新版本 ===" -ForegroundColor Cyan
Write-Host "[update] 正在拉取官方最新发布..."
powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"
Write-Host "[ok] Herdr 升级检查完成！" -ForegroundColor Green
