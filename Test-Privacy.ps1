$ErrorActionPreference = 'Stop'

# 用 ASCII 形式的 Unicode 转义传给 Windows PowerShell 5.1，避免测试管道改变中文编码。
function ConvertTo-HarmonyAsciiJson {
    param($Value)
    $json = ConvertTo-Json -InputObject $Value -Compress
    return [regex]::Replace($json, '[^\x00-\x7F]', [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return '\u{0:x4}' -f [int][char]$match.Value[0]
    })
}

# 用假的授权码和本地请求替身，验证两种模式实际发出的字段；不访问华为服务。
$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$testHome = Join-Path $projectRoot ('.codex-harmony-test-' + [guid]::NewGuid().ToString('N'))
if (-not [System.IO.Path]::GetFullPath($testHome).StartsWith(($projectRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw '隔离测试目录不在项目目录内。'
}
[void](New-Item -ItemType Directory -Path $testHome)

$oldProfile = $env:USERPROFILE
$oldPayload = $env:CODEX_HARMONY_TEST_PAYLOAD
$oldHookPath = $env:CODEX_HARMONY_HOOK_PATH
try {
    $stateDir = Join-Path $testHome 'AppData\Local\CodexHarmonyNotify'
    [void](New-Item -ItemType Directory -Path $stateDir -Force)
    $fakeSecret = ConvertTo-SecureString 'FAKE-TEST-CODE' -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $fakeSecret
    [System.IO.File]::WriteAllText((Join-Path $stateDir 'auth.dpapi'), $encrypted, (New-Object System.Text.UTF8Encoding($false)))

    $wrapperPath = Join-Path $testHome 'mock-hook.ps1'
    $wrapper = @'
param([switch]$StatusOnly)
$ErrorActionPreference = 'Stop'

function Invoke-RestMethod {
    param($Uri, $Method, $Headers, [byte[]]$Body, $ContentType, $TimeoutSec, $ErrorAction)
    [System.IO.File]::WriteAllBytes($env:CODEX_HARMONY_TEST_PAYLOAD, $Body)
    return [pscustomobject]@{ code = '0000000000' }
}
& $env:CODEX_HARMONY_HOOK_PATH -StatusOnly:$StatusOnly
'@
    [System.IO.File]::WriteAllText($wrapperPath, $wrapper, (New-Object System.Text.UTF8Encoding($false)))

    $env:USERPROFILE = $testHome
    $env:CODEX_HARMONY_HOOK_PATH = Join-Path $PSScriptRoot 'Codex-Stop-Hook.ps1'
    $payloadPath = Join-Path $testHome 'request.json'
    $env:CODEX_HARMONY_TEST_PAYLOAD = $payloadPath
    $eventJson = '{"last_assistant_message":"done ok","turn_id":"turn-for-test"}'
    $powershellFile = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath -StatusOnly | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $payloadPath)) { throw '安全联动请求未生成。' }
    $safe = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $safeMessage = $safe.data.msgContent[0]
    if ($safeMessage.content -ne 'Codex 已完成本次任务。') { throw '安全联动发送了非通用内容。' }
    if ($safeMessage.scheduleTaskName -ne 'Codex 任务') { throw '安全联动标题泄露了任务内容。' }
    if ($safeMessage.msgId -match 'turn-for-test' -or $safeMessage.scheduleTaskId -match 'turn-for-test') { throw '安全联动泄露了 Codex 回合标识。' }

    Remove-Item -LiteralPath $payloadPath
    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $payloadPath)) { throw '傻瓜式联动请求未生成。' }
    $easy = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $easyMessage = $easy.data.msgContent[0]
    if ($easyMessage.content -ne 'done ok' -or $easyMessage.msgId -notmatch 'turn-for-test' -or $easyMessage.scheduleTaskName -ne 'Codex：done ok') { throw '傻瓜式联动字段不符合预期。' }

    # 标题从实际答复提取，跳过“已完成”“总结”等空泛开头。
    $eventJson = ConvertTo-HarmonyAsciiJson -Value @{ last_assistant_message = "已完成。`n- 优化登录页面加载速度。`n- 修复按钮异常。"; turn_id = 'turn-for-test' }
    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '动态标题测试请求失败。' }
    $firstPayload = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($firstPayload.data.msgContent[0].scheduleTaskName -ne 'Codex：优化登录页面加载速度') { throw '未从第一项实际改动生成标题。' }

    $eventJson = ConvertTo-HarmonyAsciiJson -Value @{ last_assistant_message = "## 总结`n修复导出失败问题。"; turn_id = 'turn-for-test' }
    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '第二个动态标题测试请求失败。' }
    $secondPayload = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($secondPayload.data.msgContent[0].scheduleTaskName -ne 'Codex：修复导出失败问题') { throw '不同任务没有生成对应标题。' }

    # 长摘要应保留有用文字，同时只遮蔽敏感值。
    $privateText = '已完成修复，token 消耗已降低。授权码: cAFWifQQgUCz。邮箱 abc@example.com，手机 13800138000。'
    $eventJson = ConvertTo-HarmonyAsciiJson -Value @{ last_assistant_message = $privateText; turn_id = 'turn-for-test' }
    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '含敏感值的测试请求失败。' }
    $privatePayload = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $privateSummary = [string]$privatePayload.data.msgContent[0].content
    $privateTitle = [string]$privatePayload.data.msgContent[0].scheduleTaskName
    if ($privateSummary -notmatch 'token 消耗已降低' -or $privateSummary -notmatch '已完成修复') { throw '普通摘要被整段隐藏。' }
    if ($privateSummary -match 'cAFWifQQgUCz|abc@example.com|13800138000') { throw '敏感值仍出现在请求正文中。' }
    if ($privateTitle -match 'cAFWifQQgUCz|abc@example.com|13800138000') { throw '敏感值仍出现在任务标题中。' }
    if ($privateSummary -notmatch '敏感值已遮蔽|邮箱已遮蔽|手机号已遮蔽') { throw '缺少局部遮蔽提示。' }

    # 用户可能只贴出授权码，没有写“授权码”标签；卡片正文也必须遮蔽已保存的同一值。
    $eventJson = '{"last_assistant_message":"done FAKE-TEST-CODE ready","turn_id":"turn-for-test"}'
    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '授权码精确遮蔽测试请求失败。' }
    $exactPayload = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $exactSummary = [string]$exactPayload.data.msgContent[0].content
    if ($exactSummary -match 'FAKE-TEST-CODE' -or $exactSummary -notmatch '授权码已遮蔽') { throw '无标签授权码出现在卡片正文中。' }

    $eventJson = ConvertTo-HarmonyAsciiJson -Value @{ last_assistant_message = ('完成' * 300); turn_id = 'turn-for-test' }
    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '长摘要的测试请求失败。' }
    $longPayload = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $longSummary = [string]$longPayload.data.msgContent[0].content
    if ($longSummary.Length -ne 500 -or -not $longSummary.EndsWith('…')) { throw '摘要没有按 500 字上限截断。' }

    Write-Output '离线隐私验证通过：安全联动只发通用状态；傻瓜式联动使用动态标题、局部遮蔽敏感值，摘要最多 500 字。'
} finally {
    $env:USERPROFILE = $oldProfile
    $env:CODEX_HARMONY_TEST_PAYLOAD = $oldPayload
    $env:CODEX_HARMONY_HOOK_PATH = $oldHookPath
    if (([System.IO.Path]::GetFullPath($testHome).StartsWith(($projectRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)) -and (Test-Path -LiteralPath $testHome)) {
        Remove-Item -LiteralPath $testHome -Recurse -Force
    }
}
