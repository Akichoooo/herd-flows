# Cockpit Tools 上游更新/同步脚本
# 用法: powershell proxy\update-cockpit.ps1 [-SourcePath "路径"]
#       路径解析优先级: 参数 > 环境变量 COCKPIT_TOOLS_DIR > 默认路径
param(
    [string]$SourcePath = ""
)
$ErrorActionPreference = "Stop"
if (-not $SourcePath) {
    $SourcePath = if ($env:COCKPIT_TOOLS_DIR) { $env:COCKPIT_TOOLS_DIR } else { "D:\Docker Project\cockpit-tools" }
}

Write-Host "=== 检查 Cockpit Tools 上游源 ===" -ForegroundColor Cyan
if (Test-Path $SourcePath) {
    Write-Host "[ok] 找到上游源路径: $SourcePath"
    $srcSidecar = Join-Path $SourcePath "sidecars\cockpit-cliproxy"
    if (Test-Path $srcSidecar) {
        $dest = Join-Path $PSScriptRoot "sidecars\cockpit-cliproxy"
        Write-Host "[sync] 同步 sidecars\cockpit-cliproxy -> $dest ..."
        Copy-Item -Recurse -Force $srcSidecar (Join-Path $PSScriptRoot "sidecars\")
        Write-Host "[ok] cockpit-cliproxy 同步完成！" -ForegroundColor Green
    } else {
        Write-Host "[!] 未在上游源中找到 sidecars\cockpit-cliproxy" -ForegroundColor Yellow
    }
} else {
    Write-Host "[!] 未找到上游源目录: $SourcePath" -ForegroundColor Yellow
    Write-Host "    若有新版本 Git 仓库，可指定: powershell proxy\update-cockpit.ps1 -SourcePath <path>"
}
