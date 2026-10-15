$ErrorActionPreference = 'Stop'

function Get-CodexHomePath {
    # CODEX_HOME 优先；未设置时使用 Codex 的当前用户默认目录。
    $path = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        Join-Path $env:USERPROFILE '.codex'
    } else {
        $env:CODEX_HOME
    }
    return [System.IO.Path]::GetFullPath($path)
}

function Get-CodexProjectConfigPath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    $resolved = Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop
    $folder = [System.IO.Path]::GetFullPath($resolved.Path)
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw '安全联动需要一个已存在的 Git 项目目录。'
    }
    try {
        $root = & git -C $folder rev-parse --show-toplevel 2>$null
    } catch {
        throw '安全联动需要一个 Git 项目。请指定项目根目录或其子目录。'
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$root)) {
        throw '安全联动需要一个 Git 项目。请指定项目根目录或其子目录。'
    }
    return Join-Path ([System.IO.Path]::GetFullPath(([string]$root).Trim())) '.codex'
}

function Get-HarmonyHookCommand {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [switch]$StatusOnly
    )

    $scriptFile = [System.IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf)) {
        throw '找不到 Codex-Stop-Hook.ps1。'
    }
    $powershellFile = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellFile -PathType Leaf)) {
        throw '找不到 Windows PowerShell 5.1。'
    }
    $command = '"{0}" -NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -File "{1}"' -f $powershellFile, $scriptFile
    if ($StatusOnly) { $command += ' -StatusOnly' }
    return $command
}

function Test-HarmonyHookHandler {
    param($Handler)

    if ($null -eq $Handler -or [string]$Handler.type -ne 'command') {
        return $false
    }
    # 兼容旧版没有标记的本项目 Hook，只识别明确指向本脚本的命令。
    return ([string]$Handler.statusMessage -eq 'Codex Harmony Notify' -or
        [string]$Handler.command -match '(?i)(?:\\|/)Codex-Stop-Hook\.ps1(?:"|\s|$)')
}

function Read-CodexHooksConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ hooks = [pscustomobject]@{} }
    }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw '现有 hooks.json 不是有效 JSON；未修改它。'
    }
    if ($null -eq $config -or $config -isnot [pscustomobject]) {
        throw '现有 hooks.json 顶层必须是 JSON 对象；未修改它。'
    }
    if ($null -eq $config.PSObject.Properties['hooks']) {
        $config | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    } elseif ($null -eq $config.hooks -or $config.hooks -isnot [pscustomobject]) {
        throw '现有 hooks.json 的 hooks 字段必须是 JSON 对象；未修改它。'
    }
    return $config
}

function Test-HarmonyHookPresent {
    param([Parameter(Mandatory = $true)][string]$CodexHome)

    $configPath = Join-Path ([System.IO.Path]::GetFullPath($CodexHome)) 'hooks.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $false }
    $config = Read-CodexHooksConfig -Path $configPath
    if ($null -eq $config.hooks.PSObject.Properties['Stop']) { return $false }
    foreach ($group in @($config.hooks.Stop)) {
        foreach ($handler in @($group.hooks)) {
            if (Test-HarmonyHookHandler -Handler $handler) { return $true }
        }
    }
    return $false
}

function Write-CodexHooksConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Config
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    $json = $Config | ConvertTo-Json -Depth 100
    # 写入前再次解析，避免损坏 Codex 的配置。
    $null = $json | ConvertFrom-Json -ErrorAction Stop
    $temporary = Join-Path $directory ('.hooks-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backup = $null
    try {
        [System.IO.File]::WriteAllText($temporary, $json, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backup = $Path + '.backup-' + [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
            [System.IO.File]::Replace($temporary, $Path, $backup)
        } else {
            [System.IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
    return $backup
}

function Set-HarmonyCodexHook {
    param(
        [Parameter(Mandatory = $true)][string]$CodexHome,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [switch]$StatusOnly
    )

    $command = Get-HarmonyHookCommand -ScriptPath $ScriptPath -StatusOnly:$StatusOnly
    $configPath = Join-Path ([System.IO.Path]::GetFullPath($CodexHome)) 'hooks.json'
    $config = Read-CodexHooksConfig -Path $configPath
    $groups = @()
    if ($null -ne $config.hooks.PSObject.Properties['Stop']) {
        $groups = @($config.hooks.Stop)
    }

    $keptGroups = @()
    $matchingCommands = @()
    foreach ($group in $groups) {
        if ($null -eq $group -or $null -eq $group.PSObject.Properties['hooks']) {
            throw '现有 Stop Hook 格式异常；未修改 hooks.json。'
        }
        $keptHandlers = @()
        foreach ($handler in @($group.hooks)) {
            if (Test-HarmonyHookHandler -Handler $handler) {
                $matchingCommands += [string]$handler.command
            } else {
                $keptHandlers += $handler
            }
        }
        if ($keptHandlers.Count -gt 0) {
            $group.hooks = @($keptHandlers)
            $keptGroups += $group
        }
    }

    if ($matchingCommands.Count -eq 1 -and $matchingCommands[0] -eq $command) {
        return [pscustomobject]@{ Path = $configPath; Backup = $null; Changed = $false }
    }

    $newHandler = [pscustomobject]@{
        type = 'command'
        command = $command
        timeout = 20
        statusMessage = 'Codex Harmony Notify'
    }
    $keptGroups += [pscustomobject]@{ hooks = @($newHandler) }
    if ($null -eq $config.hooks.PSObject.Properties['Stop']) {
        $config.hooks | Add-Member -NotePropertyName Stop -NotePropertyValue @($keptGroups)
    } else {
        $config.hooks.Stop = @($keptGroups)
    }
    $backup = Write-CodexHooksConfig -Path $configPath -Config $config
    return [pscustomobject]@{ Path = $configPath; Backup = $backup; Changed = $true }
}

function Remove-HarmonyCodexHook {
    param([Parameter(Mandatory = $true)][string]$CodexHome)

    $configPath = Join-Path ([System.IO.Path]::GetFullPath($CodexHome)) 'hooks.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return [pscustomobject]@{ Path = $configPath; Backup = $null; Changed = $false }
    }
    $config = Read-CodexHooksConfig -Path $configPath
    if ($null -eq $config.hooks.PSObject.Properties['Stop']) {
        return [pscustomobject]@{ Path = $configPath; Backup = $null; Changed = $false }
    }
    $keptGroups = @()
    $removed = 0
    foreach ($group in @($config.hooks.Stop)) {
        if ($null -eq $group -or $null -eq $group.PSObject.Properties['hooks']) {
            throw '现有 Stop Hook 格式异常；未修改 hooks.json。'
        }
        $keptHandlers = @()
        foreach ($handler in @($group.hooks)) {
            if (Test-HarmonyHookHandler -Handler $handler) {
                $removed++
            } else {
                $keptHandlers += $handler
            }
        }
        if ($keptHandlers.Count -gt 0) {
            $group.hooks = @($keptHandlers)
            $keptGroups += $group
        }
    }
    if ($removed -eq 0) {
        return [pscustomobject]@{ Path = $configPath; Backup = $null; Changed = $false }
    }
    $config.hooks.Stop = @($keptGroups)
    $backup = Write-CodexHooksConfig -Path $configPath -Config $config
    return [pscustomobject]@{ Path = $configPath; Backup = $backup; Changed = $true }
}
