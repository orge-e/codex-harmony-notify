# 统一生成负一屏消息；授权码只在当前进程内解密，不写入日志。
$script:HarmonyEndpoint = 'https://hiboard-claw-drcn.ai.dbankcloud.cn/distribution/message/cloud/claw/msg/upload'
$script:HarmonyStateDir = Join-Path $env:USERPROFILE 'AppData\Local\CodexHarmonyNotify'
$script:HarmonySecretPath = Join-Path $script:HarmonyStateDir 'auth.dpapi'

function Get-HarmonyAuthCode {
    if (-not (Test-Path -LiteralPath $script:HarmonySecretPath)) {
        throw '尚未在本机保存鸿蒙授权码。'
    }

    $encrypted = [System.IO.File]::ReadAllText($script:HarmonySecretPath)
    $secure = ConvertTo-SecureString -String $encrypted
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Get-HarmonyShortSummary {
    param([string]$Text, [ValidateRange(1, 500)][int]$MaxLength = 500)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 'Codex 已完成本次任务。'
    }

    # 先遮蔽敏感值，再截断；普通文字仍可留在通知中。
    $clean = [regex]::Replace($Text, '(?s)```.*?(?:```|\z)', '[代码已省略]')
    $clean = [regex]::Replace($clean, 'https?://\S+', '[链接已省略]')
    $clean = [regex]::Replace($clean, '(?:[A-Za-z]:\\|\\\\)\S+', '[路径已省略]')
    $clean = [regex]::Replace($clean, '[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', '[邮箱已遮蔽]')
    $clean = [regex]::Replace($clean, '(?<!\d)1[3-9]\d{9}(?!\d)', '[手机号已遮蔽]')
    $clean = [regex]::Replace($clean, '(?<!\d)\d{17}[\dXx](?!\d)', '[证件号已遮蔽]')
    $clean = [regex]::Replace($clean, '(?i)(授权码|验证码|密码|口令|密钥|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|token|secret|credential)(\s*[:：=]\s*|\s*(?:是|为)\s*|\s+)([A-Za-z0-9_+/=.!@#$%^&*-]{4,})', '$1$2[敏感值已遮蔽]')
    $clean = [regex]::Replace($clean, '[A-Za-z0-9_+/=-]{20,}', '[长字符串已省略]')
    $clean = [regex]::Replace($clean, '[\r\n\t ]+', ' ').Trim()
    $clean = $clean.TrimStart('#', '*', '-', ' ')

    if ([string]::IsNullOrWhiteSpace($clean)) {
        return 'Codex 已完成本次任务。'
    }
    if ($clean.Length -gt $MaxLength) {
        if ($MaxLength -eq 1) { return '…' }
        $cut = $MaxLength - 1
        # 避免在表情符号的 UTF-16 代理对中间截断。
        if ($cut -gt 0 -and [char]::IsHighSurrogate($clean[$cut - 1])) { $cut-- }
        return $clean.Substring(0, $cut) + '…'
    }
    return $clean
}

function Write-HarmonyStatus {
    param([bool]$Success, [string]$Reason)

    if (-not (Test-Path -LiteralPath $script:HarmonyStateDir)) {
        [void](New-Item -ItemType Directory -Path $script:HarmonyStateDir -Force)
    }
    $record = @{
        time = [DateTimeOffset]::UtcNow.ToString('o')
        success = $Success
        reason = $Reason
    }
    $json = ConvertTo-Json -InputObject $record -Compress
    [System.IO.File]::WriteAllText((Join-Path $script:HarmonyStateDir 'last-status.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Send-HarmonyNotification {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [string]$TaskId,
        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        $TaskId = [guid]::NewGuid().ToString('N')
    }
    $TaskId = [regex]::Replace($TaskId, '[^A-Za-z0-9_-]', '')
    if ($TaskId.Length -gt 80) {
        $TaskId = $TaskId.Substring(0, 80)
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $safeName = Get-HarmonyShortSummary -Text $TaskName -MaxLength 120
    $safeSummary = Get-HarmonyShortSummary -Text $Summary
    $message = @{
        msgId = 'codex-' + $TaskId + '-' + $now
        scheduleTaskId = 'codex-' + $TaskId
        scheduleTaskName = $safeName
        summary = $safeName
        result = $Status
        content = $safeSummary
        # 华为的 Claw 卡片当前使用此来源值；任务名称标示由 Codex 完成。
        source = 'OpenClaw'
        taskFinishTime = $now
    }

    if ($DryRun) {
        return [pscustomobject]@{ Success = $true; Reason = 'dry-run'; Message = $message }
    }

    $authCode = Get-HarmonyAuthCode
    # 授权码已经需要用于发送；若它也出现在答复中，不让卡片正文重复展示。
    if (-not [string]::IsNullOrEmpty($authCode)) {
        foreach ($field in @('scheduleTaskName', 'summary', 'content')) {
            $message[$field] = ([string]$message[$field]).Replace($authCode, '[授权码已遮蔽]')
        }
    }
    $body = @{ data = @{ authCode = $authCode; msgContent = @($message) } } | ConvertTo-Json -Depth 6 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $authCode = $null
    $body = $null

    try {
        $headers = @{ 'x-trace-id' = 'codex-notify-' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddHHmmss') }
        $reply = Invoke-RestMethod -Uri $script:HarmonyEndpoint -Method Post -Headers $headers -Body $bodyBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 12 -ErrorAction Stop
        $resultCode = if ($null -ne $reply.code) { [string]$reply.code } elseif ($null -ne $reply.status) { [string]$reply.status } else { '' }
        if ($resultCode -notin @('0', '0000000000', '200', 'success', 'SUCCESS')) {
            # 只保留数字错误码；不记录响应正文，避免服务意外回显授权码。
            $safeCode = if ($resultCode -match '^[0-9]{1,12}$') { $resultCode } else { 'missing-or-hidden' }
            $reason = 'service-code-' + $safeCode
            try { Write-HarmonyStatus -Success $false -Reason $reason } catch { }
            return [pscustomobject]@{ Success = $false; Reason = $reason }
        }
        try { Write-HarmonyStatus -Success $true -Reason 'accepted' } catch { }
        return [pscustomobject]@{ Success = $true; Reason = 'accepted' }
    }
    catch {
        # 不输出服务响应或异常正文，防止服务回显授权码。
        try { Write-HarmonyStatus -Success $false -Reason 'network-or-auth-error' } catch { }
        return [pscustomobject]@{ Success = $false; Reason = 'network-or-auth-error' }
    }
}
