param([string]$ProjectPath)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -lt 1) {
    throw '安装器需要 Windows PowerShell 5.1；请使用系统自带的 powershell.exe。'
}

. (Join-Path $PSScriptRoot 'Install-Core.ps1')
. (Join-Path $PSScriptRoot 'Notification-Core.ps1')
$codexHome = Get-CodexHomePath
$hookScript = Join-Path $PSScriptRoot 'Codex-Stop-Hook.ps1'

if ($null -eq (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw '未找到 Codex 命令。请先安装并验证 Codex CLI，再运行本安装器。'
}

Write-Host 'Codex → 鸿蒙负一屏通知安装'
Write-Host "脚本目录：$PSScriptRoot"
Write-Host '1. 安全联动（默认）：指定的一个 Git 项目，只发送通用完成状态。'
Write-Host '2. 傻瓜式联动：本机所有 Codex 对话，发送完成状态和最多 500 字摘要。'
$choice = Read-Host '选择模式 [1/2，直接回车选 1]'
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
switch ($choice) {
    '1' {
        if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
            throw '安全联动需要 Git 来确认目标项目根目录。'
        }
        $projectInput = if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
            Read-Host '请输入需要通知的 Git 项目路径'
        } else {
            $ProjectPath
        }
        if ([string]::IsNullOrWhiteSpace($projectInput)) { throw '尚未指定目标项目，未修改任何配置。' }
        $configHome = Get-CodexProjectConfigPath -ProjectPath $projectInput
        $projectRoot = Split-Path -Parent $configHome
        $trackedHook = & git -C $projectRoot ls-files -- .codex/hooks.json
        if ($LASTEXITCODE -ne 0) { throw '无法检查目标项目的已跟踪文件；未修改配置。' }
        if (-not [string]::IsNullOrWhiteSpace([string]$trackedHook)) {
            throw '目标项目已把 .codex/hooks.json 纳入版本控制。为避免把本机命令提交到仓库，请先改用未跟踪的项目或手动处理该文件。'
        }
        if (Test-HarmonyHookPresent -CodexHome $codexHome) {
            throw '检测到本项目的全局 Hook。请先运行 Uninstall.ps1 移除全局 Hook，再选择安全联动，以免其他对话仍向手机推送。'
        }
        $modeName = '安全联动'
        $statusOnly = $true
        Write-Host "只在此项目加载 Hook：$(Split-Path -Parent $configHome)"
        Write-Host '项目 Hook 中包含本机脚本路径，请勿将它提交到 GitHub。'
    }
    '2' {
        $configHome = $codexHome
        $modeName = '傻瓜式联动'
        $statusOnly = $false
        Write-Host "全局 Codex 配置目录：$configHome"
    }
    default { throw '请选择 1 或 2；未修改任何配置。' }
}

Assert-HarmonyHookConfig -CodexHome $configHome
$null = Get-HarmonyHookCommand -ScriptPath $hookScript -StatusOnly:$statusOnly
Write-Host "已选择：$modeName。安装器将向 https://hiboard-claw-drcn.ai.dbankcloud.cn 发送授权码和一条固定测试消息；服务接受后自动配置 Hook。"
if (-not $statusOnly) { Write-Host '后续每次通知还会发送最多 500 字摘要；过滤无法保证识别全部私人内容。' }
Write-Host '请在下一步由本人输入授权码；输入即同意发送测试消息。安装器不会替你信任 Hook。'

$previousAuthBytes = if (Test-Path -LiteralPath $script:HarmonySecretPath -PathType Leaf) {
    # 重装失败时恢复原有加密文件，不解密旧授权码。
    [System.IO.File]::ReadAllBytes($script:HarmonySecretPath)
} else { $null }
try {
    & (Join-Path $PSScriptRoot 'Set-Auth.ps1')
    & (Join-Path $PSScriptRoot 'Send-Task.ps1') -DataFile (Join-Path $PSScriptRoot 'sample-task.json')
    $result = Set-HarmonyCodexHook -CodexHome $configHome -ScriptPath $hookScript -StatusOnly:$statusOnly
} catch {
    Restore-HarmonyAuthFile -Path $script:HarmonySecretPath -PreviousBytes $previousAuthBytes
    throw
}

if ($result.Changed) {
    Write-Host "已配置 Codex Hook：$($result.Path)"
    if ($result.Backup) { Write-Host "原配置备份：$($result.Backup)" }
} else {
    Write-Host 'Codex Hook 已存在且指向当前脚本，无需重复写入。'
}

Write-Host '电脑端已配置。请先在手机负一屏确认收到测试卡片；若未收到，不要信任 Hook，并检查关联状态。'
if ($statusOnly) {
    Write-Host '请在所选 Git 项目中启动 Codex；先信任项目配置，再输入 /hooks 检查并信任此 Stop Hook。'
} else {
    Write-Host '请重新启动 Codex CLI，输入 /hooks，检查命令后由你本人信任并启用此 Stop Hook。'
}
Write-Host '再让 Codex 完成一条不含私人信息的简单任务，并在手机上确认自动通知。'
