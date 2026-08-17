# herd-flows 依赖安装 + 自检
# 用法: powershell scripts\install-deps.ps1
$ErrorActionPreference = "Stop"

Write-Host "=== 1. herdr ===" 
$herdr = Get-Command herdr -ErrorAction SilentlyContinue
if (-not $herdr) {
    Write-Host "[install] herdr (Windows beta)..."
    powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"
} else {
    Write-Host "[ok] herdr $($herdr.Source)"
}

Write-Host "=== 2. Docker ===" 
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker info *>$null
    if ($LASTEXITCODE -eq 0) { Write-Host "[ok] docker daemon running" }
    else { Write-Host "[!] docker installed but daemon not running — start Docker Desktop" }
} else {
    Write-Host "[!] docker not installed — https://www.docker.com/products/docker-desktop"
}

Write-Host "=== 3. cliproxy image ===" 
$img = docker images -q cockpit-tools/cockpit-cliproxy:local 2>$null
if ($img) { Write-Host "[ok] cockpit-cliproxy:local image exists" }
else {
    Write-Host "[build] cockpit-cliproxy:local..."
    docker build -t cockpit-tools/cockpit-cliproxy:local -f gateway/Dockerfile.cockpit-cliproxy gateway/
}

Write-Host "=== 4. claude CLI ===" 
if (Get-Command claude -ErrorAction SilentlyContinue) { Write-Host "[ok] claude CLI" }
else { Write-Host "[!] claude CLI not found — npm i -g @anthropic-ai/claude-code" }

Write-Host "=== done. run: powershell runner\herdr-pool.ps1 -Ensure ===" 
