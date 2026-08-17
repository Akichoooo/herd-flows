# subclaw v2 runner — herdr 编排 + cockpit-cliproxy 网关池 + 验证者循环
# 用法（任意主模型/人 直接调用）:
#   herdr-pool.ps1 -Ensure                 确保 herdr session 活着 + 生成 worker settings + 自检网关
#   herdr-pool.ps1 -Dispatch "任务描述" [-Profile flash] [-Name w1] [-Verify]
#   herdr-pool.ps1 -Read w1                读 worker 输出
#   herdr-pool.ps1 -Status [w1]            查 worker/agent 状态
#   herdr-pool.ps1 -Verify w1 -Task "任务"  手动跑验证者
#   herdr-pool.ps1 -Clean w1               关闭 worker 所在 pane
param(
  [switch]$Ensure, [switch]$Dispatch, [switch]$Read, [switch]$Status, [switch]$Verify, [switch]$Clean,
  [string]$Task = "", [string]$Profile = "", [string]$Name = "", [int]$Port = 0,
  [switch]$NoVerify, [int]$TimeoutMs = 0
)
$ErrorActionPreference = "Stop"
$CfgPath = Join-Path $PSScriptRoot "config.json"
$Cfg = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Session = $Cfg.PSObject.Properties['herdrSession'].Value
if (-not $Session) { $Session = "subclaw" }
if (-not $Profile) { $Profile = $Cfg.defaults.profile }
if (-not $TimeoutMs) { $TimeoutMs = $Cfg.defaults.timeoutMs }

# ---- herdr.exe 定位 ----
function Find-Herdr {
  $p = $Cfg.PSObject.Properties['herdrExe'].Value
  if ($p -and (Test-Path $p)) { return $p }
  $cmd = Get-Command herdr -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $rel = "C:\Users\92586\.herdr\packages\standalone\releases"
  if (Test-Path $rel) {
    $latest = Get-ChildItem $rel -Directory | Sort-Object Name -Descending | Select-Object -First 1
    $exe = Join-Path $latest.FullName "herdr.exe"
    if (Test-Path $exe) { return $exe }
  }
  throw "herdr.exe not found (install: powershell irm https://herdr.dev/install.ps1 | iex)"
}
$Herdr = Find-Herdr
$DD = "--"  # PS 5.1 在函数调用里会吞裸的 -- 字面量，经变量传递则保留
# @args splatting 也有同类问题，统一走 cmd 拼接
function Hdr {
  $parts = @($Herdr, '--session', $Session) + @($args)
  $line = ($parts | ForEach-Object { if ("$_" -match '\s') { '"{0}"' -f $_ } else { "$_" } }) -join ' '
  if ($env:SUBCLAW_DEBUG) { Write-Host "[dbg] $line" }
  cmd /c $line 2>&1
}

# ---- worker settings 生成（按 dispatch 时的实际 port 动态写，不能预固定）----
function Write-WorkerSettings([string]$ProfileName, [int]$Port) {
  $dir = Join-Path $PSScriptRoot "worker-settings"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $prof = $Cfg.workerProfiles.$ProfileName
  if (-not $prof) { throw "unknown profile '$ProfileName'" }
  $settings = @{
    env = @{
      ANTHROPIC_BASE_URL  = "$($Cfg.gateway.baseUrl):$Port"
      ANTHROPIC_AUTH_TOKEN = $Cfg.gateway.apiKey
      ANTHROPIC_API_KEY    = $Cfg.gateway.apiKey
      ANTHROPIC_MODEL      = $prof.model
      ANTHROPIC_DEFAULT_SONNET_MODEL = $prof.model
      ANTHROPIC_DEFAULT_HAIKU_MODEL  = $prof.model
      ANTHROPIC_DEFAULT_OPUS_MODEL   = $prof.model
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
    }
  } | ConvertTo-Json -Depth 5
  $file = Join-Path $dir "$ProfileName.settings.json"
  Set-Content -Path $file -Value $settings -Encoding UTF8
  return $file
}

function Ensure-WorkerSettings {
  $dir = Join-Path $PSScriptRoot "worker-settings"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return $dir
}

# ---- 网关自检 ----
function Test-Gateway([int]$Port) {
  try {
    $r = Invoke-RestMethod -Uri "$($Cfg.gateway.baseUrl):$Port/v1/models" -Headers @{Authorization="Bearer $($Cfg.gateway.apiKey)"} -TimeoutSec 5
    return $true
  } catch { return $false }
}

# ---- 验证者（定义须先于 Dispatch 分支的调用）----
function Invoke-Verify([string]$WorkerName, [string]$TaskText, [string]$OutputText) {
  $vProfName = $Cfg.verifier.profile
  $vName = "$WorkerName-verifier"
  $vProf = $Cfg.workerProfiles.$vProfName
  $dir = Ensure-WorkerSettings
  $settingsFile = Write-WorkerSettings $vProfName $vProf.port
  $cwd = (Get-Location).Path
  $split = Hdr pane split --current --direction down --cwd $cwd --no-focus | Out-String
  $paneId = if ($split -match '"pane_id":"([^"]+)"') { $Matches[1] } else { throw "verifier split failed" }
  Start-Sleep -Seconds 2
  Hdr agent start $vName --kind claude --pane $paneId --timeout 60000 $DD --settings $settingsFile | Out-Null
  $vp = $Cfg.verifier.promptTemplate.Replace("{task}", $TaskText).Replace("{output}", $OutputText)
  Hdr agent prompt $vName $vp --wait --timeout 300000 | Out-Null
  $raw = Hdr agent read $vName --source recent-unwrapped --lines 60 | Out-String
  Hdr pane close --pane $paneId 2>$null | Out-Null
  $verdict = "FAIL"; $redo = ""
  if ($raw -match '"verdict"\s*:\s*"PASS"') { $verdict = "PASS" }
  elseif ($raw -match '"redo"\s*:\s*"([^"]{1,400})') { $redo = $Matches[1] }
  return @{ verdict = $verdict; redo = $redo; raw = $raw }
}

# ---- 命令实现 ----
if ($Ensure) {
  $out = Hdr status | Out-String
  if ($out -match "not running") {
    Write-Host "[!] herdr session '$Session' 未运行。请在新终端窗口执行: herdr --session $Session （保持开着）"
    Write-Host "    或后台启动: Start-Process -WindowStyle Hidden `"$Herdr`" -ArgumentList '--session','$Session'"
    exit 1
  }
  Write-Host "[ok] herdr session '$Session' 运行中"
  $dir = Ensure-WorkerSettings
  Write-Host "[ok] worker settings -> $dir"
  foreach ($p in $Cfg.gateway.ports) {
    $ok = Test-Gateway $p
    Write-Host ("[{0}] gateway :{1}" -f ($(if ($ok) {"ok"} else {"DOWN"})), $p)
  }
  exit 0
}

if (-not $Name) { $Name = "w" + (Get-Date -Format "HHmmss") }

# ---- split 智能选向：默认 down（保持宽度，避免连续 right 切成 1 列窄条）。宽 pane 切 right ----
function Split-Pane {
  $cwd = (Get-Location).Path
  $cur = Hdr pane current --current | Out-String
  $paneId = if ($cur -match '"pane_id":"([^"]+)"') { $Matches[1] } else { "" }
  $dir = "down"
  if ($paneId) {
    $layout = Hdr pane layout --pane $paneId | Out-String
    if ($layout -match '"width"\s*:\s*(\d+)' -and [int]$Matches[1] -ge 120) { $dir = "right" }
  }
  $split = Hdr pane split --current --direction $dir --cwd $cwd --no-focus | Out-String
  return $split
}

if ($Dispatch) {
  if (-not $Task) { throw "-Task required" }
  $prof = $Cfg.workerProfiles.$Profile
  if (-not $prof) { throw "unknown profile '$Profile' (available: $($Cfg.workerProfiles.PSObject.Properties.Name -join ', '))" }
  $port = if ($Port) { $Port } else { $prof.port }
  if (-not (Test-Gateway $port)) { throw "gateway :$port DOWN — docker compose -f compose.subclaw-pool.yml up -d first" }
  $dir = Ensure-WorkerSettings
  $settingsFile = Write-WorkerSettings $Profile $port

  # 0. 同名 agent 已活着则复用（省 pane；不重复 split）
  $existing = Hdr agent list | Out-String
  $reused = $existing -match ('"name":"' + $Name + '"')

  if ($reused) {
    Write-Host "[1/4] reuse live agent '$Name'"
    $paneId = if ($existing -match ('"name":"' + $Name + '"[^}]*?"pane_id":"([^"]+)"')) { $Matches[1] } else { "" }
  } else {
    # 1. split pane（智能方向，保持调用者 cwd，不抢焦点）
    $split = Split-Pane
    $paneId = if ($split -match '"pane_id":"([^"]+)"') { $Matches[1] } else { throw "split failed: $split" }
    Write-Host "[1/4] pane $paneId"

    # 2. agent start（--settings 注入网关）
    Start-Sleep -Seconds 2
    $startOut = Hdr agent start $Name --kind claude --pane $paneId --timeout 60000 $DD --settings $settingsFile | Out-String
    if ($startOut -match '"agent_status":"(idle|working)"') { Write-Host "[2/4] agent '$Name' started ($($prof.model) via :$port)" }
    else { throw "agent start failed: $startOut" }
  }

  # 3. prompt + wait
  Write-Host "[3/4] dispatching task ..."
  $promptOut = Hdr agent prompt $Name $Task --wait --timeout $TimeoutMs | Out-String
  $st = if ($promptOut -match '"agent_status":"([^"]+)"') { $Matches[1] } else { "unknown" }
  Write-Host "[3/4] worker state: $st"

  # 4. read 产出
  $output = Hdr agent read $Name --source recent-unwrapped --lines $Cfg.defaults.readLines | Out-String
  Write-Host "===== worker output ====="
  Write-Host $output

  # 5. 验证者循环
  $useVerifier = $Cfg.verifier.enabled -and (-not $NoVerify)
  if ($useVerifier -and $st -ne "blocked") {
    for ($round = 1; $round -le $Cfg.verifier.maxRounds; $round++) {
      Write-Host "===== verify round $round ====="
      $vOut = Invoke-Verify -WorkerName $Name -TaskText $Task -OutputText $output
      Write-Host $vOut.raw
      if ($vOut.verdict -eq "PASS") { Write-Host "[✓] PASS"; break }
      if ($round -ge $Cfg.verifier.maxRounds) { Write-Host "[✗] FAIL after $round rounds"; break }
      Write-Host "[↻] redo -> $Name"
      Hdr agent prompt $Name $vOut.redo --wait --timeout $TimeoutMs | Out-Null
      $output = Hdr agent read $Name --source recent-unwrapped --lines $Cfg.defaults.readLines | Out-String
      Write-Host "----- worker redo output -----"
      Write-Host $output
    }
  }
  exit 0
}

if ($Read) {
  Hdr agent read $Name --source recent-unwrapped --lines $Cfg.defaults.readLines
  exit 0
}
if ($Status) {
  if ($Name) { Hdr agent get $Name } else { Hdr agent list }
  exit 0
}
if ($Verify) {
  if (-not $Task) { throw "-Task required (任务原文)" }
  $output = Hdr agent read $Name --source recent-unwrapped --lines $Cfg.defaults.readLines | Out-String
  $r = Invoke-Verify -WorkerName $Name -TaskText $Task -OutputText $output
  Write-Host $r.raw
  Write-Host "verdict: $($r.verdict)"
  exit 0
}
if ($Clean) {
  $info = Hdr agent get $Name | Out-String
  if ($info -match '"pane_id":"([^"]+)"') { Hdr pane close --pane $Matches[1] | Out-Null; Write-Host "[ok] closed $($Matches[1])" }
  exit 0
}

Write-Host "usage: herdr-pool.ps1 -Ensure | -Dispatch `<task`> [-Profile flash] [-Verify] | -Read `<name`> | -Status [`<name`>] | -Verify `<name`> -Task `<task`> | -Clean `<name`>"
