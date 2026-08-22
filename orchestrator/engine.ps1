# herd-flows 核心编排调度引擎 (Core Orchestration Engine)
# 职责: 协调 Herdr 终端牧场、Cockpit 反代网关、Worker 羊群与 Verifier 牧羊犬，执行高省 Token 派发与自闭环质检。

param(
    [object]$Config,
    [string]$BaseDir
)

. (Join-Path $PSScriptRoot "adapters\herdr-adapter.ps1")
. (Join-Path $PSScriptRoot "adapters\gateway-adapter.ps1")
. (Join-Path $PSScriptRoot "profile-manager.ps1")
. (Join-Path $PSScriptRoot "verifier.ps1")

$HerdrExe = Find-HerdrExe -ExplicitPath $Config.PSObject.Properties['herdrExe'].Value
$Session  = if ($Config.herdrSession) { $Config.herdrSession } else { "subclaw" }

function Execute-Ensure {
    Write-Host "=== [1/3] Herdr 终端牧场检测 ===" -ForegroundColor Cyan
    $alive = Test-HerdrSessionAlive -HerdrExe $HerdrExe -Session $Session
    if (-not $alive) {
        Write-Host "[!] Herdr 会话 '$Session' 未在运行。" -ForegroundColor Yellow
        Write-Host "    请先在终端启动: powershell scripts\start-herdr.ps1" -ForegroundColor Yellow
        Write-Host "    或后台启动: Start-Process -WindowStyle Hidden `"$HerdrExe`" -ArgumentList '--session','$Session'"
        exit 1
    }
    Write-Host "[ok] Herdr 会话 '$Session' 运行中 (牧场正常)" -ForegroundColor Green

    Write-Host "=== [2/3] Worker 动态配置目录 ===" -ForegroundColor Cyan
    $setDir = Ensure-SettingsDir -BaseDir $BaseDir
    Write-Host "[ok] worker-settings -> $setDir" -ForegroundColor Green

    Write-Host "=== [3/3] Cockpit 反代网关池健康探测 ===" -ForegroundColor Cyan
    $pool = Probe-GatewayPool -BaseUrl $Config.gateway.baseUrl -Ports $Config.gateway.ports -ApiKey $Config.gateway.apiKey
    foreach ($p in $Config.gateway.ports) {
        $ok = $pool[$p]
        $tag = if ($ok) { "[ok]" } else { "[DOWN]" }
        $color = if ($ok) { "Green" } else { "Red" }
        Write-Host ("{0} 网关端口 :{1}" -f $tag, $p) -ForegroundColor $color
    }
    exit 0
}

function Execute-Dispatch {
    param(
        [string]$Task,
        [string]$Profile,
        [string]$Name,
        [int]$Port = 0,
        [switch]$NoVerify,
        [switch]$Async,
        [int]$TimeoutMs = 0
    )

    if (-not $Task) { throw "-Task 参数必填 (任务描述或 Brief 文件路径)" }
    if (-not $Profile) { $Profile = $Config.defaults.profile }
    if (-not $TimeoutMs) { $TimeoutMs = $Config.defaults.timeoutMs }
    if (-not $Name) { $Name = "w" + (Get-Date -Format "HHmmss") }

    $prof = $Config.workerProfiles.$Profile
    if (-not $prof) {
        throw "未知的 Profile '$Profile' (可选: $($Config.workerProfiles.PSObject.Properties.Name -join ', '))"
    }

    # 1. 确定网关端口 (支持指定，否则用 profile 默认端口，支持故障自动寻可用端口)
    $targetPort = if ($Port -gt 0) { $Port } else { $prof.port }
    if (-not (Test-GatewayPort -BaseUrl $Config.gateway.baseUrl -Port $targetPort -ApiKey $Config.gateway.apiKey)) {
        $alt = Get-HealthyGatewayPort -BaseUrl $Config.gateway.baseUrl -Ports $Config.gateway.ports -ApiKey $Config.gateway.apiKey
        if ($alt -gt 0) {
            Write-Host "[warn] 端口 :$targetPort 不通，自动切换到可用端口 :$alt" -ForegroundColor Yellow
            $targetPort = $alt
        } else {
            throw "所有网关端口均不可用，请启动网关: powershell scripts\start-proxy.ps1"
        }
    }

    # 2. 动态生成 settings.json
    $settingsFile = Generate-WorkerSettings -BaseDir $BaseDir -Config $Config -ProfileName $Profile -ActualPort $targetPort

    # 3. 检查是否有同名活着的 Agent（省分屏；复用已存在 Agent）
    $liveAgents = Get-PaneAgentInfo -HerdrExe $HerdrExe -Session $Session
    $reused = $liveAgents -match ('"name":"' + $Name + '"')

    if ($reused) {
        Write-Host "[1/4] 复用运行中的 Agent '$Name'" -ForegroundColor Cyan
    } else {
        # 智能分屏
        $paneId = Split-SmartPane -HerdrExe $HerdrExe -Session $Session
        Write-Host "[1/4] 牧场分屏成功 -> Pane $paneId" -ForegroundColor Cyan

        # 启动 Agent
        Start-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $Name -PaneId $paneId -SettingsFile $settingsFile -TimeoutMs 60000 | Out-Null
        Write-Host "[2/4] Worker '$Name' 已就绪 (模型: $($prof.model) 经由 :$targetPort)" -ForegroundColor Green
    }

    # 4. 派发任务
    Write-Host "[3/4] 正在向 Worker '$Name' 下发任务 ..." -ForegroundColor Cyan
    if ($Async) {
        Prompt-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $Name -PromptText $Task -NoWait | Out-Null
        Write-Host "[ok] 任务已异步下发给 '$Name'，可随时使用: powershell runner\herdr-pool.ps1 -Read $Name 查看进度" -ForegroundColor Green
        exit 0
    }

    $promptRes = Prompt-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $Name -PromptText $Task -TimeoutMs $TimeoutMs
    Write-Host "[3/4] Worker 状态: $($promptRes.status)" -ForegroundColor Yellow

    # 5. 抓取 Worker 初步产出
    $readLines = if ($Config.defaults.readLines) { $Config.defaults.readLines } else { 120 }
    $output = Read-PaneAgentOutput -HerdrExe $HerdrExe -Session $Session -AgentName $Name -Lines $readLines
    Write-Host "`n===== Worker 交付物 =====" -ForegroundColor Cyan
    Write-Host $output

    # 6. 牧羊犬质检验收循环 (Verifier Loop)
    $useVerifier = $Config.verifier.enabled -and (-not $NoVerify)
    if ($useVerifier -and $promptRes.status -ne "blocked") {
        $maxRounds = if ($Config.verifier.maxRounds) { $Config.verifier.maxRounds } else { 2 }
        for ($round = 1; $round -le $maxRounds; $round++) {
            Write-Host "`n===== 牧羊犬质检验收 (第 $round 轮) =====" -ForegroundColor Magenta
            $vResult = Invoke-TaskVerification -HerdrExe $HerdrExe -Session $Session -Config $Config -WorkerName $Name -TaskText $Task -OutputText $output -BaseDir $BaseDir
            Write-Host $vResult.raw

            if ($vResult.verdict -eq "PASS") {
                Write-Host "[✓] 质检合格: PASS (放行交付)" -ForegroundColor Green
                break
            }

            if ($round -ge $maxRounds) {
                Write-Host "[✗] 达到最大质检轮次 ($round 轮)，质检结论: FAIL" -ForegroundColor Red
                break
            }

            Write-Host "[↻] 质检不合格，生成重做指令打回 Worker '$Name' ..." -ForegroundColor Yellow
            Write-Host "    打回原因: $($vResult.reasons)" -ForegroundColor Yellow
            $redoPrompt = if ($vResult.redo) { $vResult.redo } else { "请根据上述质检意见重新完善交付物。" }
            
            Prompt-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $Name -PromptText $redoPrompt -TimeoutMs $TimeoutMs | Out-Null
            $output = Read-PaneAgentOutput -HerdrExe $HerdrExe -Session $Session -AgentName $Name -Lines $readLines
            Write-Host "`n----- Worker 重做交付物 -----" -ForegroundColor Cyan
            Write-Host $output
        }
    }
    exit 0
}

function Execute-Read([string]$Name) {
    if (-not $Name) { throw "-Name 必填 (Worker 标识)" }
    $lines = if ($Config.defaults.readLines) { $Config.defaults.readLines } else { 120 }
    $out = Read-PaneAgentOutput -HerdrExe $HerdrExe -Session $Session -AgentName $Name -Lines $lines
    Write-Host $out
    exit 0
}

function Execute-Status([string]$Name = "") {
    $info = Get-PaneAgentInfo -HerdrExe $HerdrExe -Session $Session -AgentName $Name
    Write-Host $info
    exit 0
}

function Execute-Verify([string]$Name, [string]$Task) {
    if (-not $Name) { throw "-Name 必填" }
    if (-not $Task) { throw "-Task 必填 (任务原文)" }
    $lines = if ($Config.defaults.readLines) { $Config.defaults.readLines } else { 120 }
    $output = Read-PaneAgentOutput -HerdrExe $HerdrExe -Session $Session -AgentName $Name -Lines $lines
    $r = Invoke-TaskVerification -HerdrExe $HerdrExe -Session $Session -Config $Config -WorkerName $Name -TaskText $Task -OutputText $output -BaseDir $BaseDir
    Write-Host $r.raw
    Write-Host "`n结论: $($r.verdict)" -ForegroundColor (if ($r.verdict -eq "PASS") { "Green" } else { "Red" })
    exit 0
}

function Execute-Clean([string]$Name) {
    if (-not $Name) { throw "-Name 必填" }
    $info = Get-PaneAgentInfo -HerdrExe $HerdrExe -Session $Session -AgentName $Name
    if ($info -match '"pane_id":"([^"]+)"') {
        Close-Pane -HerdrExe $HerdrExe -Session $Session -PaneId $Matches[1]
        Write-Host "[ok] 已安全关闭 Worker '$Name' (Pane $($Matches[1]))" -ForegroundColor Green
    } else {
        Write-Host "[!] 未找到 Agent '$Name' 对应的 Pane" -ForegroundColor Yellow
    }
    exit 0
}
