# herd-flows 依赖安装 + 环境自检脚本
# 用法: powershell scripts\install-deps.ps1
$ErrorActionPreference = "Stop"
$RootDir = Split-Path $PSScriptRoot -Parent

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       herd-flows 依赖检查与初始化         " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. 检查 Herdr
Write-Host "`n=== 1. Herdr 终端牧场运行时 ===" -ForegroundColor Cyan
. (Join-Path $RootDir "vendor\herdr\install-herdr.ps1")

# 2. 检查 Docker
Write-Host "`n=== 2. Docker 环境 ===" -ForegroundColor Cyan
if (Get-Command docker -ErrorAction SilentlyContinue) {
    # EAP=Stop 下重定向原生 stderr 会抛异常，探测期间局部降级
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { docker info 2>$null | Out-Null } finally { $ErrorActionPreference = $prevEap }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[ok] Docker 守护进程运行中" -ForegroundColor Green
    } else {
        Write-Host "[!] Docker 已安装但服务未启动 — 请启动 Docker Desktop" -ForegroundColor Yellow
    }
} else {
    Write-Host "[!] 未检测到 Docker — 可选安装: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
}

# 3. 检查 / 构建 cockpit-cliproxy 镜像
Write-Host "`n=== 3. Cockpit Cliproxy 本地镜像 ===" -ForegroundColor Cyan
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[!] 未检测到 docker 命令，跳过镜像检查" -ForegroundColor Yellow
} else {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { docker info 2>$null | Out-Null } finally { $ErrorActionPreference = $prevEap }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Docker 守护进程未启动，跳过镜像检查 — 请启动 Docker Desktop" -ForegroundColor Yellow
    } elseif (docker images -q cockpit-tools/cockpit-cliproxy:local) {
        Write-Host "[ok] cockpit-cliproxy:local 镜像已就绪" -ForegroundColor Green
    } else {
        Write-Host "[build] 正在从本地 proxy 模块独立构建 cockpit-cliproxy:local ..." -ForegroundColor Yellow
        $dockerfile = Join-Path $RootDir "proxy\Dockerfile.cockpit-cliproxy"
        $proxyDir = Join-Path $RootDir "proxy"
        docker build -t cockpit-tools/cockpit-cliproxy:local -f $dockerfile $proxyDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[✗] 镜像构建失败，请检查上方 docker 输出" -ForegroundColor Red
            exit 1
        }
        Write-Host "[ok] 镜像构建成功！" -ForegroundColor Green
    }
}

# 4. 检查 Claude CLI
Write-Host "`n=== 4. Claude CLI (Worker 执行引擎) ===" -ForegroundColor Cyan
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "[ok] Claude CLI 已安装" -ForegroundColor Green
} else {
    Write-Host "[!] Claude CLI 未找到 — 安装命令: npm i -g @anthropic-ai/claude-code" -ForegroundColor Yellow
}

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "  环境就绪！可运行: powershell scripts\start-all.ps1" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
