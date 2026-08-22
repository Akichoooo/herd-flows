# Worker 档位管理与动态环境注入 (Profile Manager)
# 职责: 管理 Worker 档位（flash / deepseek / glm 等），按 dispatch 时的实际端口动态生成 settings.json。

function Ensure-SettingsDir([string]$BaseDir) {
    $dir = Join-Path $BaseDir "worker-settings"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    return $dir
}

function Generate-WorkerSettings([string]$BaseDir, [object]$Config, [string]$ProfileName, [int]$ActualPort) {
    $dir = Ensure-SettingsDir $BaseDir
    $prof = $Config.workerProfiles.$ProfileName
    if (-not $prof) {
        throw "未知的 Worker 档位 Profile: '$ProfileName'"
    }

    $baseUrl = $Config.gateway.baseUrl
    $apiKey  = $Config.gateway.apiKey

    $settings = @{
        env = @{
            ANTHROPIC_BASE_URL                      = "$baseUrl`:$ActualPort"
            ANTHROPIC_AUTH_TOKEN                   = $apiKey
            ANTHROPIC_API_KEY                      = $apiKey
            ANTHROPIC_MODEL                        = $prof.model
            ANTHROPIC_DEFAULT_SONNET_MODEL         = $prof.model
            ANTHROPIC_DEFAULT_HAIKU_MODEL          = $prof.model
            ANTHROPIC_DEFAULT_OPUS_MODEL           = $prof.model
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
        }
    } | ConvertTo-Json -Depth 5

    $filePath = Join-Path $dir "$ProfileName.settings.json"
    Set-Content -Path $filePath -Value $settings -Encoding UTF8
    return $filePath
}
