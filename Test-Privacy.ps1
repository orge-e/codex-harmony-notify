$ErrorActionPreference = 'Stop'

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
    if ($safeMessage.msgId -match 'turn-for-test' -or $safeMessage.scheduleTaskId -match 'turn-for-test') { throw '安全联动泄露了 Codex 回合标识。' }

    Remove-Item -LiteralPath $payloadPath
    $eventJson | & $powershellFile -NoProfile -ExecutionPolicy RemoteSigned -File $wrapperPath | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $payloadPath)) { throw '傻瓜式联动请求未生成。' }
    $easy = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $easyMessage = $easy.data.msgContent[0]
    if ($easyMessage.content -ne 'done ok' -or $easyMessage.msgId -notmatch 'turn-for-test') { throw '傻瓜式联动字段不符合预期。' }

    Write-Output '离线隐私验证通过：安全联动仅发送通用状态和随机 ID，傻瓜式联动发送简短摘要。'
} finally {
    $env:USERPROFILE = $oldProfile
    $env:CODEX_HARMONY_TEST_PAYLOAD = $oldPayload
    $env:CODEX_HARMONY_HOOK_PATH = $oldHookPath
    if (([System.IO.Path]::GetFullPath($testHome).StartsWith(($projectRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)) -and (Test-Path -LiteralPath $testHome)) {
        Remove-Item -LiteralPath $testHome -Recurse -Force
    }
}
