# Herdr 终端牧场适配器 (Herdr Pasture Adapter)
# 职责: 封装底层 Herdr CLI / 协议调用，隔离 Herdr 版本差异，为编排引擎提供统一接口。

$DD = "--"  # PS 5.1 在函数调用里会吞裸的 -- 字面量，经变量传递则保留

function Find-HerdrExe([string]$ExplicitPath = "") {
    if ($ExplicitPath -and (Test-Path $ExplicitPath)) { return $ExplicitPath }
    $cmd = Get-Command herdr -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $rel = "C:\Users\92586\.herdr\packages\standalone\releases"
    if (Test-Path $rel) {
        $latest = Get-ChildItem $rel -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $exe = Join-Path $latest.FullName "herdr.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    throw "herdr.exe 未找到，请执行: powershell vendor\herdr\install-herdr.ps1"
}

function Invoke-Hdr([string]$HerdrExe, [string]$Session, [string[]]$HdrArgs) {
    $parts = @($HerdrExe, '--session', $Session) + $HdrArgs
    $line = ($parts | ForEach-Object { if ("$_" -match '\s') { '"{0}"' -f $_ } else { "$_" } }) -join ' '
    if ($env:SUBCLAW_DEBUG) { Write-Host "[dbg-hdr] $line" -ForegroundColor DarkGray }
    $out = cmd /c $line 2>&1
    return $out
}

function Test-HerdrSessionAlive([string]$HerdrExe, [string]$Session) {
    $out = Invoke-Hdr $HerdrExe $Session @("status") | Out-String
    if ($out -match "not running" -or $LASTEXITCODE -ne 0) {
        return $false
    }
    return $true
}

function Split-SmartPane([string]$HerdrExe, [string]$Session, [string]$Cwd = "") {
    if (-not $Cwd) { $Cwd = (Get-Location).Path }
    $cur = Invoke-Hdr $HerdrExe $Session @("pane", "current", "--current") | Out-String
    $curPaneId = if ($cur -match '"pane_id":"([^"]+)"') { $Matches[1] } else { "" }
    $dir = "down"
    if ($curPaneId) {
        $layout = Invoke-Hdr $HerdrExe $Session @("pane", "layout", "--pane", $curPaneId) | Out-String
        if ($layout -match '"width"\s*:\s*(\d+)' -and [int]$Matches[1] -ge 120) {
            $dir = "right"
        }
    }
    $split = Invoke-Hdr $HerdrExe $Session @("pane", "split", "--current", "--direction", $dir, "--cwd", $Cwd, "--no-focus") | Out-String
    if ($split -match '"pane_id":"([^"]+)"') {
        return $Matches[1]
    }
    throw "Pane 分屏失败: $split"
}

function Start-PaneAgent([string]$HerdrExe, [string]$Session, [string]$AgentName, [string]$PaneId, [string]$SettingsFile, [string]$Kind = "claude", [int]$TimeoutMs = 60000) {
    Start-Sleep -Seconds 1
    $global:DD = "--"
    $argsList = @("agent", "start", $AgentName, "--kind", $Kind, "--pane", $PaneId, "--timeout", "$TimeoutMs", $global:DD, "--settings", $SettingsFile)
    $startOut = Invoke-Hdr $HerdrExe $Session $argsList | Out-String
    if ($startOut -match '"agent_status":"(idle|working)"') {
        return $true
    }
    throw "Agent '$AgentName' 启动失败: $startOut"
}

function Prompt-PaneAgent([string]$HerdrExe, [string]$Session, [string]$AgentName, [string]$PromptText, [int]$TimeoutMs = 900000, [switch]$NoWait) {
    $argsList = if ($NoWait) {
        @("agent", "prompt", $AgentName, $PromptText)
    } else {
        @("agent", "prompt", $AgentName, $PromptText, "--wait", "--timeout", "$TimeoutMs")
    }
    $promptOut = Invoke-Hdr $HerdrExe $Session $argsList | Out-String
    $status = if ($promptOut -match '"agent_status":"([^"]+)"') { $Matches[1] } else { "unknown" }
    return @{
        status = $status
        raw    = $promptOut
    }
}

function Read-PaneAgentOutput([string]$HerdrExe, [string]$Session, [string]$AgentName, [int]$Lines = 120) {
    $output = Invoke-Hdr $HerdrExe $Session @("agent", "read", $AgentName, "--source", "recent-unwrapped", "--lines", "$Lines") | Out-String
    return $output
}

function Get-PaneAgentInfo([string]$HerdrExe, [string]$Session, [string]$AgentName = "") {
    if ($AgentName) {
        return Invoke-Hdr $HerdrExe $Session @("agent", "get", $AgentName) | Out-String
    } else {
        return Invoke-Hdr $HerdrExe $Session @("agent", "list") | Out-String
    }
}

function Close-Pane([string]$HerdrExe, [string]$Session, [string]$PaneId) {
    Invoke-Hdr $HerdrExe $Session @("pane", "close", "--pane", $PaneId) | Out-Null
}
