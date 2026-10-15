$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Notification-Core.ps1')

# Read-Host 的安全输入不会在终端显示，也不会进入命令历史。
$secret = Read-Host '请在此输入手机新生成的授权码' -AsSecureString
if ($null -eq $secret -or $secret.Length -lt 8) {
    throw '授权码为空或长度不符合预期。'
}

if (-not (Test-Path -LiteralPath $script:HarmonyStateDir)) {
    [void](New-Item -ItemType Directory -Path $script:HarmonyStateDir -Force)
}
$encrypted = ConvertFrom-SecureString -SecureString $secret
[System.IO.File]::WriteAllText($script:HarmonySecretPath, $encrypted, (New-Object System.Text.UTF8Encoding($false)))
Write-Output '授权码已加密保存在当前 Windows 用户目录；内容未显示。'
