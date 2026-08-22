# Herdr 终端牧场适配器 (Herdr Pasture Adapter)
# 职责: 封装底层 Herdr CLI / 协议调用，隔离 Herdr 版本差异，为编排引擎提供统一接口。

$DD = "--"  # PS 5.1 在函数调用里会吞裸的 -- 字面量，经变量传递则保留

function Find-HerdrExe([string]$ExplicitPath = "") {
    if ($ExplicitPath -and (Test-Path $ExplicitPath)) { return $ExplicitPath }
    $cmd = Get-Command herdr -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $rel = Join-Path $env:USERPROFILE ".herdr\packages\standalone\releases"
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
    # 直传数组参数（不走 cmd /c 拼串）：消除 cmd 元字符（% & ^ | 等）注入与内嵌引号丢失。
    # PS 5.1 会为含空白参数自动加引号但不转义内嵌双引号，这里按 MS argv 规则预转义为 \"，
    # 由对端（Rust/CRT）解析还原。`--` 仍经 $DD 变量传递，规避 PS 解析裸 -- 的问题。
    $allArgs = @('--session', $Session) + @($HdrArgs)
    if ($env:SUBCLAW_DEBUG) { Write-Host ("[dbg-hdr] " + ($allArgs -join ' ')) -ForegroundColor DarkGray }
    $safeArgs = foreach ($a in $allArgs) {
        $s = "$a" -replace '"', '\"'
        # 含空白的参数会被 PS 自动加引号，末尾反斜杠需翻倍，否则 \" 会被对端当作转义引号
        if ($s -match '\s' -and $s -match '\\+$') { $s += '\' }
        $s
    }

    # EAP=Stop 时 PS 5.1 对原生程序 stderr 重定向会直接抛异常，调用期间局部降级
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $HerdrExe @safeArgs 2>&1
    } finally {
        $ErrorActionPreference = $prevEap
    }
    $flat = foreach ($line in $out) {
        if ($line -is [System.Management.Automation.ErrorRecord]) { $line.Exception.Message } else { "$line" }
    }
    return $flat
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
    $argsList = @("agent", "start", $AgentName, "--kind", $Kind, "--pane", $PaneId, "--timeout", "$TimeoutMs", $DD, "--settings", $SettingsFile)
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
