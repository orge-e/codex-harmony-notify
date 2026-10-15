param([string]$ProjectPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Install-Core.ps1')

$configHome = if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    Get-CodexHomePath
} else {
    Get-CodexProjectConfigPath -ProjectPath $ProjectPath
}
$result = Remove-HarmonyCodexHook -CodexHome $configHome
if ($result.Changed) {
    Write-Host "已移除本项目的 Codex Stop Hook：$($result.Path)"
    Write-Host "修改前配置备份：$($result.Backup)"
} else {
    Write-Host '未发现本项目的 Codex Stop Hook，无需修改配置。'
}

Write-Host '已保存的鸿蒙授权码仍留在当前 Windows 用户目录；如要清除，可在手机端停止关联后删除本机 auth.dpapi 文件。'
Write-Host '如 Codex 正在运行，请重启它以加载更新后的 Hook 配置。'
