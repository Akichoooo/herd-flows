# 启动 Cockpit Tools 图形化配置界面 (Web / GUI)
# 用法: powershell scripts\start-gui.ps1
$ErrorActionPreference = "Stop"
$CockpitDir = "D:\Docker Project\cockpit-tools"

Write-Host "=== 启动 Cockpit Tools 图形化配置中心 ===" -ForegroundColor Cyan

if (Test-Path $CockpitDir) {
    Write-Host "[ok] 找到 Cockpit Tools 源码目录: $CockpitDir"
    
    # 检查是否安装了 node/npm
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "[start] 正在启动 Cockpit Web 图形化配置面板..." -ForegroundColor Green
        Write-Host "        启动后请在浏览器访问: http://localhost:5173" -ForegroundColor Yellow
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$CockpitDir'; npm run dev"
    } else {
        Write-Host "[!] 未检测到 npm 命令，请安装 Node.js 或直接使用 Cockpit 桌面客户端。" -ForegroundColor Yellow
    }
} else {
    Write-Host "[!] 未找到 Cockpit Tools 目录: $CockpitDir" -ForegroundColor Yellow
}
