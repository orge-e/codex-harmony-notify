param(
    [Parameter(Mandatory = $true)][string]$DataFile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Notification-Core.ps1')

# 只读取用户明确指定的任务 JSON；试运行不读取授权码，也不联网。
$resolved = (Resolve-Path -LiteralPath $DataFile -ErrorAction Stop).Path
$task = [System.IO.File]::ReadAllText($resolved, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$task.task_name) -or [string]::IsNullOrWhiteSpace([string]$task.task_result)) {
    throw '任务 JSON 需要 task_name 和 task_result。'
}
$summary = Get-HarmonyShortSummary -Text ([string]$task.task_content)
$result = Send-HarmonyNotification -TaskName ([string]$task.task_name) -Status ([string]$task.task_result) -Summary $summary -TaskId ([string]$task.task_id) -DryRun:$DryRun
if ($DryRun) {
    $result.Message | ConvertTo-Json -Depth 4
} elseif ($result.Success) {
    Write-Output '华为服务已接受推送请求，请在手机负一屏核对。'
} else {
    throw "推送未通过：$($result.Reason)。授权码和服务响应已隐藏。"
}
