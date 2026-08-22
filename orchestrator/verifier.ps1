# 牧羊犬质检评估器 (Verifier / Sheepdog Inspector)
# 职责: 独立 Pane 运行质检 Agent，依据任务契约严格判定 Worker 产出，输出 PASS 或 FAIL + redo 指令。

. (Join-Path $PSScriptRoot "adapters\herdr-adapter.ps1")
. (Join-Path $PSScriptRoot "adapters\gateway-adapter.ps1")
. (Join-Path $PSScriptRoot "profile-manager.ps1")

function Invoke-TaskVerification {
    param(
        [string]$HerdrExe,
        [string]$Session,
        [object]$Config,
        [string]$WorkerName,
        [string]$TaskText,
        [string]$OutputText,
        [string]$BaseDir
    )

    $vProfName = $Config.verifier.profile
    if (-not $vProfName) { $vProfName = "deepseek" }
    $vProf = $Config.workerProfiles.$vProfName
    if (-not $vProf) { throw "Verifier profile '$vProfName' not defined in config" }

    # 1. 探测 Verifier 网关端口
    $vPort = $vProf.port
    if (-not (Test-GatewayPort -BaseUrl $Config.gateway.baseUrl -Port $vPort -ApiKey $Config.gateway.apiKey)) {
        # 尝试容错寻找其他可用端口
        $altPort = Get-HealthyGatewayPort -BaseUrl $Config.gateway.baseUrl -Ports $Config.gateway.ports -ApiKey $Config.gateway.apiKey
        if ($altPort -gt 0) { $vPort = $altPort }
        else { throw "Verifier 网关不可用 (所有端口 DOWN)" }
    }

    # 2. 生成 Verifier settings
    $settingsFile = Generate-WorkerSettings -BaseDir $BaseDir -Config $Config -ProfileName $vProfName -ActualPort $vPort

    # 3. 在 Herdr 中分屏拉起 Verifier
    $vPaneId = Split-SmartPane -HerdrExe $HerdrExe -Session $Session -Cwd (Get-Location).Path
    $vName = "$WorkerName-verifier"

    try {
        Start-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $vName -PaneId $vPaneId -SettingsFile $settingsFile -TimeoutMs 60000 | Out-Null
        
        # 4. 组装验收 Prompt
        $template = $Config.verifier.promptTemplate
        if (-not $template) {
            $tplPath = Join-Path $PSScriptRoot "templates\verifier-default.txt"
            if (Test-Path $tplPath) { $template = Get-Content $tplPath -Raw -Encoding UTF8 }
            else { $template = "判定工作者输出是否合格。只输出一行 JSON：{`"verdict`":`"PASS`"} 或 {`"verdict`":`"FAIL`",`"reasons`":`"...`",`"redo`":`"...`"}`n`n【任务原文】`n{task}`n`n【工作者输出】`n{output}" }
        }
        $vPrompt = $template.Replace("{task}", $TaskText).Replace("{output}", $OutputText)

        # 5. 发送质检 Prompt 并等待判定
        $pRes = Prompt-PaneAgent -HerdrExe $HerdrExe -Session $Session -AgentName $vName -PromptText $vPrompt -TimeoutMs 300000
        
        # 6. 读取质检回显
        $raw = Read-PaneAgentOutput -HerdrExe $HerdrExe -Session $Session -AgentName $vName -Lines 60
    } finally {
        # 7. 关闭 Verifier Pane 释放资源
        Close-Pane -HerdrExe $HerdrExe -Session $Session -PaneId $vPaneId
    }

    # 8. 解析 JSON 判定结果
    $verdict = "FAIL"
    $redo = ""
    $reasons = ""

    if ($raw -match '"verdict"\s*:\s*"PASS"') {
        $verdict = "PASS"
    } elseif ($raw -match '(?s)\{.*?"verdict"\s*:\s*"FAIL".*?\}') {
        $verdict = "FAIL"
        if ($raw -match '"reasons"\s*:\s*"([^"]+)"') { $reasons = $Matches[1] }
        if ($raw -match '"redo"\s*:\s*"([^"]+)"') { $redo = $Matches[1] }
    } elseif ($raw -match '"redo"\s*:\s*"([^"]{1,500})') {
        $redo = $Matches[1]
    }

    return @{
        verdict = $verdict
        reasons = $reasons
        redo    = $redo
        raw     = $raw
    }
}
