# 启动 Cockpit 反代网关池
# 用法: powershell scripts\start-proxy.ps1
$ErrorActionPreference = "Stop"
$RootDir = Split-Path $PSScriptRoot -Parent
$ProxyDir = Join-Path $RootDir "proxy"
$ComposeFile = Join-Path $ProxyDir "compose.subclaw-pool.yml"
$EnvFile = Join-Path $ProxyDir ".env"

Write-Host "=== 启动 Cockpit Tools 反代网关池 ===" -ForegroundColor Cyan

if (-not (Test-Path $EnvFile)) {
    $exampleEnv = Join-Path $ProxyDir ".env.example"
    Write-Host "[init] 未找到 proxy\.env，正在根据 .env.example 初始化..." -ForegroundColor Yellow
    Copy-Item $exampleEnv $EnvFile
    Write-Host "[!] 请在 proxy\.env 中填入有效的厂商 API Keys！" -ForegroundColor Yellow
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "[docker] 启动 4 端口网关池 (:1456 ~ :1459) ..."
    docker compose -f $ComposeFile --env-file $EnvFile up -d
    Write-Host "[ok] 网关池启动指令已发送！" -ForegroundColor Green
} else {
    Write-Host "[!] 未检测到 Docker 命令，若使用 Windows 本地 Cockpit 桌面客户端，请确保本地代理服务已在对应端口开启。" -ForegroundColor Yellow
}
