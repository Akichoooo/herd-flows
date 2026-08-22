# Herdr 安装与自检脚本 (Windows)
# 用法: powershell vendor\herdr\install-herdr.ps1
$ErrorActionPreference = "Stop"

Write-Host "=== 检查 Herdr 运行时 ===" -ForegroundColor Cyan

$cmd = Get-Command herdr -ErrorAction SilentlyContinue
if ($cmd) {
    Write-Host "[ok] PATH 中找到 Herdr: $($cmd.Source)" -ForegroundColor Green
    exit 0
}

$rel = "C:\Users\92586\.herdr\packages\standalone\releases"
if (Test-Path $rel) {
    $latest = Get-ChildItem $rel -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) {
        $exe = Join-Path $latest.FullName "herdr.exe"
        if (Test-Path $exe) {
            Write-Host "[ok] 在用户目录找到 Herdr: $exe" -ForegroundColor Green
            exit 0
        }
    }
}

Write-Host "[install] 未找到 herdr.exe，正在从官方源安装 (Windows beta)..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"
Write-Host "[ok] Herdr 安装完成！" -ForegroundColor Green
