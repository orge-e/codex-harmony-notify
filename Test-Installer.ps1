$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Install-Core.ps1')

# 在临时 Codex 目录验证合并、重复运行及卸载；不会联网或读取真实授权码。
$testHome = Join-Path $PSScriptRoot ('.codex-harmony-test-' + [guid]::NewGuid().ToString('N'))
if (-not [System.IO.Path]::GetFullPath($testHome).StartsWith(([System.IO.Path]::GetFullPath($PSScriptRoot) + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw '隔离测试目录不在项目目录内。'
}
[void](New-Item -ItemType Directory -Path $testHome)
try {
    $hooksPath = Join-Path $testHome 'hooks.json'
    $existing = '{"description":"keep me","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other-notifier.exe"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"other-start.exe"}]}]}}'
    [System.IO.File]::WriteAllText($hooksPath, $existing, (New-Object System.Text.UTF8Encoding($false)))

    $first = Set-HarmonyCodexHook -CodexHome $testHome -ScriptPath (Join-Path $PSScriptRoot 'Codex-Stop-Hook.ps1')
    if (-not $first.Changed -or -not (Test-Path -LiteralPath $first.Backup)) { throw '首次安装或备份失败。' }

    $second = Set-HarmonyCodexHook -CodexHome $testHome -ScriptPath (Join-Path $PSScriptRoot 'Codex-Stop-Hook.ps1')
    if ($second.Changed) { throw '重复安装应保持配置不变。' }

    $config = [System.IO.File]::ReadAllText($hooksPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $ours = @($config.hooks.Stop | ForEach-Object { $_.hooks } | Where-Object { Test-HarmonyHookHandler -Handler $_ })
    if ($ours.Count -ne 1) { throw '本项目 Hook 数量错误。' }
    if (@($config.hooks.Stop | ForEach-Object { $_.hooks } | Where-Object { $_.command -eq 'other-notifier.exe' }).Count -ne 1) { throw '原有 Stop Hook 丢失。' }
    if (@($config.hooks.SessionStart).Count -ne 1 -or $config.description -ne 'keep me') { throw '其他配置丢失。' }
    if ([System.IO.File]::ReadAllBytes($hooksPath)[0] -eq 239) { throw 'hooks.json 不应包含 UTF-8 BOM。' }

    $removed = Remove-HarmonyCodexHook -CodexHome $testHome
    if (-not $removed.Changed -or -not (Test-Path -LiteralPath $removed.Backup)) { throw '卸载或备份失败。' }
    $after = [System.IO.File]::ReadAllText($hooksPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if (@($after.hooks.Stop | ForEach-Object { $_.hooks } | Where-Object { Test-HarmonyHookHandler -Handler $_ }).Count -ne 0) { throw '本项目 Hook 未移除。' }
    if (@($after.hooks.Stop | ForEach-Object { $_.hooks } | Where-Object { $_.command -eq 'other-notifier.exe' }).Count -ne 1) { throw '卸载删除了其他 Hook。' }

    $projectRoot = Join-Path $testHome 'one-project'
    [void](New-Item -ItemType Directory -Path $projectRoot)
    & git -C $projectRoot init -q
    if ($LASTEXITCODE -ne 0) { throw '隔离 Git 项目创建失败。' }
    $projectChild = Join-Path $projectRoot 'child'
    [void](New-Item -ItemType Directory -Path $projectChild)
    $freshHome = Get-CodexProjectConfigPath -ProjectPath $projectChild
    if ($freshHome -ne (Join-Path $projectRoot '.codex')) { throw '项目范围识别错误。' }
    $fresh = Set-HarmonyCodexHook -CodexHome $freshHome -ScriptPath (Join-Path $PSScriptRoot 'Codex-Stop-Hook.ps1') -StatusOnly
    if (-not $fresh.Changed -or $fresh.Backup -or -not (Test-Path -LiteralPath $fresh.Path)) { throw '安全联动全新安装失败。' }
    $safeConfig = [System.IO.File]::ReadAllText($fresh.Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$safeConfig.hooks.Stop[0].hooks[0].command -notmatch ' -StatusOnly$') { throw '安全联动没有启用仅状态模式。' }

    $invalidHome = Join-Path $testHome 'invalid'
    [void](New-Item -ItemType Directory -Path $invalidHome)
    $invalidPath = Join-Path $invalidHome 'hooks.json'
    [System.IO.File]::WriteAllText($invalidPath, '{invalid json', (New-Object System.Text.UTF8Encoding($false)))
    $failedSafely = $false
    try {
        $null = Set-HarmonyCodexHook -CodexHome $invalidHome -ScriptPath (Join-Path $PSScriptRoot 'Codex-Stop-Hook.ps1')
    } catch {
        $failedSafely = $true
    }
    if (-not $failedSafely -or [System.IO.File]::ReadAllText($invalidPath) -ne '{invalid json') { throw '无效 JSON 应保持原样并停止。' }

    $failedEarly = $false
    try { Assert-HarmonyHookConfig -CodexHome $invalidHome } catch { $failedEarly = $true }
    if (-not $failedEarly) { throw '无效配置应在读取授权码前被发现。' }

    $secretPath = Join-Path $testHome 'auth.dpapi'
    [System.IO.File]::WriteAllText($secretPath, 'new-code')
    Restore-HarmonyAuthFile -Path $secretPath -PreviousBytes $null
    if (Test-Path -LiteralPath $secretPath) { throw '首次安装失败后不应留下新授权码。' }
    $oldBytes = [System.Text.Encoding]::UTF8.GetBytes('old-code')
    [System.IO.File]::WriteAllText($secretPath, 'new-code')
    Restore-HarmonyAuthFile -Path $secretPath -PreviousBytes $oldBytes
    if ([System.IO.File]::ReadAllText($secretPath) -ne 'old-code') { throw '重装失败后未恢复原加密文件。' }

    Write-Output '安装器离线验证通过：项目范围、Hook 合并与备份、重复安装、无 BOM、提前识别无效配置、失败回滚授权码。'
} finally {
    if (([System.IO.Path]::GetFullPath($testHome).StartsWith(([System.IO.Path]::GetFullPath($PSScriptRoot) + '\'), [System.StringComparison]::OrdinalIgnoreCase)) -and (Test-Path -LiteralPath $testHome)) {
        Remove-Item -LiteralPath $testHome -Recurse -Force
    }
}
