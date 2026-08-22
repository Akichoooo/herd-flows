# 牧羊犬质检评估器 (Verifier / Sheepdog Inspector)
# 职责: 独立 Pane 运行质检 Agent，依据任务契约严格判定 Worker 产出，输出 PASS 或 FAIL + redo 指令。
# 判定协议: 质检 Agent 在回复末尾输出标记行 `VERDICT: PASS|FAIL`（FAIL 时附 REASONS:/REDO: 行）。
#           引擎取「最后一次出现」的 VERDICT 标记解析——prompt 回显中的格式说明不会抢先命中；
#           且模板中的示例值写作 <PASS 或 FAIL>，不含可被正则匹配的字面判定。

. (Join-Path $PSScriptRoot "adapters\herdr-adapter.ps1")
. (Join-Path $PSScriptRoot "adapters\gateway-adapter.ps1")
. (Join-Path $PSScriptRoot "profile-manager.ps1")

function Get-VerifierPromptTemplate([object]$Config) {
    # 优先 config.verifier.promptTemplate 覆盖；默认读 templates/verifier-default.txt（唯一事实来源）
    if ($Config.verifier.promptTemplate) { return $Config.verifier.promptTemplate }
    $tplPath = Join-Path $PSScriptRoot "templates\verifier-default.txt"
    if (Test-Path $tplPath) { return (Get-Content $tplPath -Raw -Encoding UTF8) }
    return "你是任务验收员。若任务涉及文件交付，先用工具实际查看文件确认真实完整，不要只信工作者自述。`n在回复最末尾输出判定: VERDICT: <PASS 或 FAIL>；若 FAIL 再跟两行 REASONS: <一行原因> 与 REDO: <一行重做指令>。`n`n【任务原文】`n{task}`n`n【工作者输出】`n{output}"
}

function Start-VerifierAgent {
    # 拉起常驻质检 Agent（同一 Worker 的多轮质检复用同一实例，避免每轮冷启动）
    # 返回 @{ name; paneId }
    param(
        [string]$HerdrExe,
        [string]$Session,
        [object]$Config,
        [string]$BaseDir,
        [string]$WorkerName
    )

    $vProfName = $Config.verifier.profile
    if (-not $vProfName) { $vProfName = "deepseek" }
    $vProf = $Config.workerProfiles.$vProfName
    if (-not $vProf) { throw "Verifier profile '$vProfName' not defined in config" }

    $vPort = $vProf.port
    if (-not (Test-GatewayPort -BaseUrl $Config.gateway.baseUrl -Port $vPort -ApiKey $Config.gateway.apiKey)) {
        $altPort = Get-HealthyGatewayPort -BaseUrl $Config.gateway.baseUrl -Ports $Config.gateway.ports -ApiKey $Config.gateway.apiKey
        if ($altPort -gt 0) { $vPort = $altPort }
        else { throw "Verifier 网关不可用 (所有端口 DOWN)" }
    }

    $settingsFile = Generate-WorkerSettings -BaseDir $BaseDir -Config $Config -ProfileName $vProfName -ActualPort $vPort
    $vPaneId = Split-SmartPane -HerdrExe $HerdrExe -Session $Session -Cwd (Get-Location).Path
    $vName = "$WorkerName-verifier"

    Start-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $vName -PaneId $vPaneId -SettingsFile $settingsFile -TimeoutMs 60000 | Out-Null
    return @{ name = $vName; paneId = $vPaneId }
}

function Invoke-VerifierRound {
    # 对既有 Verifier Agent 发送一轮质检 Prompt 并解析判定
    # 返回 @{ verdict; reasons; redo; raw }
    param(
        $Verifier,
        [string]$HerdrExe,
        [string]$Session,
        [string]$TaskText,
        [string]$OutputText,
        [object]$Config
    )

    $vPrompt = (Get-VerifierPromptTemplate $Config).Replace("{task}", $TaskText).Replace("{output}", $OutputText)
    Prompt-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $Verifier.name -PromptText $vPrompt -TimeoutMs 300000 | Out-Null
    $raw = Read-PaneAgentOutput -HerdrExe $HerdrExe -Session $Session -AgentName $Verifier.name -Lines 80

    return Parse-VerifierVerdict -Raw ($raw | Out-String)
}

function Stop-VerifierAgent {
    param([string]$HerdrExe, [string]$Session, $Verifier)
    if ($Verifier -and $Verifier.paneId) {
        Close-Pane -HerdrExe $HerdrExe -Session $Session -PaneId $Verifier.paneId
    }
}

function Parse-VerifierVerdict([string]$Raw) {
    $result = @{ verdict = "FAIL"; reasons = ""; redo = ""; raw = $Raw }

    $hits = [regex]::Matches($Raw, '(?im)^[^\r\n]*VERDICT\s*:\s*(PASS|FAIL)\b.*$')
    if ($hits.Count -eq 0) {
        $result.reasons = "质检员未输出可解析的 VERDICT 标记行（视为 FAIL，避免漏检）"
        return $result
    }

    # 取最后一次出现的 VERDICT：模型真正的判定在其回复末尾，早于它的都是 prompt 回显
    $last = $hits[$hits.Count - 1]
    $result.verdict = $last.Groups[1].Value.ToUpper()

    if ($result.verdict -eq "FAIL") {
        $tail = $Raw.Substring($last.Index)
        $m1 = [regex]::Match($tail, '(?im)^[^\r\n]*REASONS\s*:\s*(.+)$')
        $m2 = [regex]::Match($tail, '(?im)^[^\r\n]*REDO\s*:\s*(.+)$')
        if ($m1.Success) { $result.reasons = $m1.Groups[1].Value.Trim() }
        if ($m2.Success) { $result.redo = $m2.Groups[1].Value.Trim() }
    }
    return $result
}

function Invoke-TaskVerification {
    # 单发封装：拉起 -> 质检一轮 -> 回收（供 -Verify 手动质检与兼容旧调用）
    param(
        [string]$HerdrExe,
        [string]$Session,
        [object]$Config,
        [string]$WorkerName,
        [string]$TaskText,
        [string]$OutputText,
        [string]$BaseDir
    )

    $verifier = Start-VerifierAgent -HerdrExe $HerdrExe -Session $Session -Config $Config -BaseDir $BaseDir -WorkerName $WorkerName
    try {
        return Invoke-VerifierRound -Verifier $verifier -HerdrExe $HerdrExe -Session $Session -TaskText $TaskText -OutputText $OutputText -Config $Config
    } finally {
        Stop-VerifierAgent -HerdrExe $HerdrExe -Session $Session -Verifier $verifier
    }
}
