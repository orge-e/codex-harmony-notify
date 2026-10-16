param([switch]$StatusOnly)

$ErrorActionPreference = 'Stop'
$stage = 'load'

function Complete-HarmonyHook {
    # Codex 的 Stop Hook 要求标准输出是 JSON，空对象表示不改变原答复。
    [Console]::Out.Write('{}')
    exit 0
}

try {
    . (Join-Path $PSScriptRoot 'Notification-Core.ps1')
    $stage = 'state-check'
    if (-not (Test-Path -LiteralPath $script:HarmonySecretPath)) {
        Complete-HarmonyHook
    }
    if (Test-Path -LiteralPath (Join-Path $script:HarmonyStateDir 'paused.flag')) {
        Complete-HarmonyHook
    }

    # Codex 把 Hook 事件作为 JSON 送入标准输入；不读取完整会话记录。
    $stage = 'input-read'
    # Codex 的事件 JSON 使用 UTF-8；Windows PowerShell 5.1 默认输入编码可能不同。
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Length -gt 1048576) {
        Complete-HarmonyHook
    }
    $stage = 'parse'
    $event = $raw | ConvertFrom-Json
    $stage = 'sanitize'
    if ($StatusOnly) {
        # 安全联动不处理答复正文，也不把 Codex 回合标识发给云端。
        $summary = 'Codex 已完成本次任务。'
        $taskName = 'Codex 任务'
        $taskId = ''
    } else {
        $summary = Get-HarmonyShortSummary -Text ([string]$event.last_assistant_message)
        $taskName = Get-HarmonyTaskTitle -Text ([string]$event.last_assistant_message)
        $taskId = [string]$event.turn_id
    }
    $stage = 'send'
    $result = Send-HarmonyNotification -TaskName $taskName -Status '任务已完成' -Summary $summary -TaskId $taskId
    # 网络故障不应阻断 Codex 的答复。
    $null = $result
}
catch {
    # 本机仅保存通用失败状态；不记录事件正文或授权码。
    try { Write-HarmonyStatus -Success $false -Reason ('hook-error-' + $stage) } catch { }
}
Complete-HarmonyHook
