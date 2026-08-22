# herd-flows 统一调度入口 (Unified Runner Entrypoint)
# 用法:
#   powershell runner\herdr-pool.ps1 -Ensure                              # 检查牧场与网关状态
#   powershell runner\herdr-pool.ps1 -Dispatch "<task>" [-Profile flash]  # 派发任务 (带质检闭环)
#   powershell runner\herdr-pool.ps1 -Dispatch "<task>" -Async            # 异步非阻塞派发
#   powershell runner\herdr-pool.ps1 -Read <name>                         # 读取 Worker 回显
#   powershell runner\herdr-pool.ps1 -Status [<name>]                     # 查看 Worker 状态
#   powershell runner\herdr-pool.ps1 -Verify <name> -Task "<task>"        # 手动执行质检
#   powershell runner\herdr-pool.ps1 -Clean <name>                        # 清理回收 Worker

param(
    [switch]$Ensure,
    [switch]$Dispatch,
    [switch]$Read,
    [switch]$Status,
    [switch]$Verify,
    [switch]$Clean,
    [string]$Task = "",
    [string]$Profile = "",
    [string]$Name = "",
    [int]$Port = 0,
    [switch]$NoVerify,
    [switch]$Async,
    [int]$TimeoutMs = 0
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path $PSScriptRoot -Parent
$CfgPath = Join-Path $PSScriptRoot "config.json"
$Cfg = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json

# 加载编排调度核心引擎
$EngineScript = Join-Path $RootDir "orchestrator\engine.ps1"
. $EngineScript -Config $Cfg -BaseDir $PSScriptRoot

if ($Ensure)   { Execute-Ensure }
if ($Dispatch) { Execute-Dispatch -Task $Task -Profile $Profile -Name $Name -Port $Port -NoVerify:$NoVerify -Async:$Async -TimeoutMs $TimeoutMs }
if ($Read)     { Execute-Read -Name $Name }
if ($Status)   { Execute-Status -Name $Name }
if ($Verify)   { Execute-Verify -Name $Name -Task $Task }
if ($Clean)    { Execute-Clean -Name $Name }

Write-Host "用法: herdr-pool.ps1 -Ensure | -Dispatch `<task`> [-Profile flash] [-Async] | -Read `<name`> | -Status [`<name`>] | -Verify `<name`> -Task `<task`> | -Clean `<name`>"
