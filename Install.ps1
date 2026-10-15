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
Write-Host '1. 安全联动（默认）：仅指定的一个 Git 项目；发送授权码及通用完成状态，不发送答复摘要或 Codex 回合标识。'
Write-Host '2. 傻瓜式联动：同一 CODEX_HOME 下所有本机 Codex 对话；发送授权码、完成状态和最多 120 字摘要。'
$choice = Read-Host '请选择模式，直接回车使用安全联动 [1/2]'
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
switch ($choice) {
    '1' {
        if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
            throw '安全联动需要 Git 来确认目标项目根目录。'
        }
        $projectInput = if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
            Read-Host '请输入需要启用通知的 Git 项目目录绝对路径'
        } else {
            $ProjectPath
        }
        if ([string]::IsNullOrWhiteSpace($projectInput)) { throw '尚未指定目标项目，未修改任何配置。' }
        $configHome = Get-CodexProjectConfigPath -ProjectPath $projectInput
        if (Test-HarmonyHookPresent -CodexHome $codexHome) {
            throw '检测到本项目的全局 Hook。请先运行 Uninstall.ps1 移除全局 Hook，再选择安全联动，以免其他对话仍向手机推送。'
        }
        $modeName = '安全联动'
        $statusOnly = $true
        Write-Host "只在此项目加载 Hook：$(Split-Path -Parent $configHome)"
        Write-Host '请勿把项目内生成的 .codex/hooks.json 提交到 GitHub。'
    }
    '2' {
        $configHome = $codexHome
        $modeName = '傻瓜式联动'
        $statusOnly = $false
        Write-Host "全局 Codex 配置目录：$configHome"
    }
    default { throw '请选择 1 或 2；未修改任何配置。' }
}

Write-Host '发送目标：https://hiboard-claw-drcn.ai.dbankcloud.cn'
Write-Host "已选择：$modeName。测试通知会发送不含私人内容的固定文本。"
if (-not $statusOnly) { Write-Host '摘要过滤无法保证识别全部私人内容。' }
Write-Host '安装器不会替你信任 Hook。'

$proceed = Read-Host '确认继续并发送一条测试通知？输入 Y 继续'
if ($proceed -notmatch '^(?i:y|yes)$') {
    Write-Host '已取消，未读取授权码，也未修改 Codex Hook。'
    exit 0
}

# 先展示不含授权码的消息，再让用户本人在当前终端遮蔽输入。
& (Join-Path $PSScriptRoot 'Send-Task.ps1') -DataFile (Join-Path $PSScriptRoot 'sample-task.json') -DryRun
$previousAuthBytes = if (Test-Path -LiteralPath $script:HarmonySecretPath -PathType Leaf) {
    # 重装测试失败时恢复原有加密文件，不解密旧授权码。
    [System.IO.File]::ReadAllBytes($script:HarmonySecretPath)
} else { $null }
& (Join-Path $PSScriptRoot 'Set-Auth.ps1')

try {
    & (Join-Path $PSScriptRoot 'Send-Task.ps1') -DataFile (Join-Path $PSScriptRoot 'sample-task.json')
} catch {
    if ($null -ne $previousAuthBytes) {
        [System.IO.File]::WriteAllBytes($script:HarmonySecretPath, $previousAuthBytes)
    }
    throw '测试推送未通过。Codex Hook 未修改；若此前已有授权码，旧加密文件已恢复。请检查手机关联和网络后重试。'
}

$received = Read-Host '请检查手机负一屏。已收到测试卡片？输入 Y 继续配置自动通知'
if ($received -notmatch '^(?i:y|yes)$') {
    if ($null -ne $previousAuthBytes) {
        [System.IO.File]::WriteAllBytes($script:HarmonySecretPath, $previousAuthBytes)
    }
    Write-Host '手机收件未确认，Codex Hook 未修改。可检查关联状态后重新运行安装器。'
    exit 0
}
$previousAuthBytes = $null

$result = Set-HarmonyCodexHook -CodexHome $configHome -ScriptPath $hookScript -StatusOnly:$statusOnly
if ($result.Changed) {
    Write-Host "已配置 Codex Hook：$($result.Path)"
    if ($result.Backup) { Write-Host "原配置备份：$($result.Backup)" }
} else {
    Write-Host 'Codex Hook 已存在且指向当前脚本，无需重复写入。'
}

if ($statusOnly) {
    Write-Host '请在所选 Git 项目中启动 Codex；先信任项目配置，再输入 /hooks 检查并信任此 Stop Hook。'
} else {
    Write-Host '请重新启动 Codex CLI，输入 /hooks，检查命令后由你本人信任并启用此 Stop Hook。'
}
Write-Host '再让 Codex 完成一条不含私人信息的简单任务，并在手机上确认自动通知。'
