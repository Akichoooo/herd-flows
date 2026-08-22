# Cockpit Tools 反代网关适配器 (Gateway Adapter)
# 职责: 封装反代网关池探测、多端口连通性检查、429 容错与负载轮换。

function Test-GatewayPort([string]$BaseUrl, [int]$Port, [string]$ApiKey, [int]$TimeoutSec = 4) {
    try {
        $uri = "$BaseUrl`:$Port/v1/models"
        $headers = @{ Authorization = "Bearer $ApiKey" }
        $res = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Probe-GatewayPool([string]$BaseUrl, [int[]]$Ports, [string]$ApiKey) {
    $results = @{}
    foreach ($p in $Ports) {
        $ok = Test-GatewayPort -BaseUrl $BaseUrl -Port $p -ApiKey $ApiKey
        $results[$p] = $ok
    }
    return $results
}

function Get-HealthyGatewayPort([string]$BaseUrl, [int[]]$Ports, [string]$ApiKey, [int]$PreferredPort = 0) {
    if ($PreferredPort -gt 0) {
        if (Test-GatewayPort -BaseUrl $BaseUrl -Port $PreferredPort -ApiKey $ApiKey) {
            return $PreferredPort
        }
    }
    foreach ($p in $Ports) {
        if (Test-GatewayPort -BaseUrl $BaseUrl -Port $p -ApiKey $ApiKey) {
            return $p
        }
    }
    return 0
}
