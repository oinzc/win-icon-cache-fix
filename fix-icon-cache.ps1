<#
.SYNOPSIS
    Backup and rebuild the Windows 10/11 icon cache to fix blank white taskbar/desktop icons.

.DESCRIPTION
    When desktop shortcuts are moved into folders, moved across drives, or updated,
    Windows Explorer may cache stale icon references in IconCache.db / iconcache_*.db
    and render blank white sheet icons on the taskbar or desktop.
    This script safely backs up existing icon cache files, briefly restarts explorer.exe
    to release file locks, removes stale icon cache files, and triggers a shell refresh.

.PARAMETER DryRun
    Preview detected icon cache files and planned actions without modifying any files or restarting Explorer.

.PARAMETER RefreshOnly
    Run a non-destructive shell icon refresh (ie4uinit.exe -show and SHChangeNotify) without restarting Explorer.

.PARAMETER IncludeThumbCache
    Also include thumbcache_*.db files in cleanup (excluded by default).

.PARAMETER NoBackup
    Skip backing up existing cache files before removal.

.PARAMETER Force
    Skip interactive confirmation prompt.

.PARAMETER UseScheduledTask
    Relaunch explorer.exe via a temporary interactive scheduled task instead of Start-Process.
    Useful when invoked from wrappers or agent terminals that terminate child processes on exit.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RefreshOnly,
    [switch]$IncludeThumbCache,
    [switch]$NoBackup,
    [switch]$Force,
    [switch]$UseScheduledTask
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ShellIconRefresh {
    $ie4uinit = Join-Path $env:WINDIR 'System32\ie4uinit.exe'
    if (Test-Path -LiteralPath $ie4uinit) {
        & $ie4uinit -show | Out-Null
    }

    if (-not ([System.Management.Automation.PSTypeName]'WinIconCacheFix.ShellNative').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinIconCacheFix {
    public static class ShellNative {
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
    }
}
"@
    }

    # SHCNE_ASSOCCHANGED = 0x08000000, SHCNF_IDLIST = 0x0000
    [WinIconCacheFix.ShellNative]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Get-IconCacheTargets {
    param(
        [switch]$WithThumbCache
    )

    $targets = New-Object System.Collections.Generic.List[System.IO.FileInfo]

    $localIconCache = Join-Path $env:LOCALAPPDATA 'IconCache.db'
    if (Test-Path -LiteralPath $localIconCache) {
        $item = Get-Item -LiteralPath $localIconCache -Force -ErrorAction SilentlyContinue
        if ($item -is [System.IO.FileInfo]) {
            $targets.Add($item)
        }
    }

    $explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    if (Test-Path -LiteralPath $explorerDir) {
        Get-ChildItem -LiteralPath $explorerDir -Filter 'iconcache*.db' -File -Force -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object { $targets.Add($_) }

        if ($WithThumbCache) {
            Get-ChildItem -LiteralPath $explorerDir -Filter 'thumbcache*.db' -File -Force -ErrorAction SilentlyContinue |
                Sort-Object Name |
                ForEach-Object { $targets.Add($_) }
        }
    }

    return $targets
}

function Start-ExplorerInteractive {
    param(
        [switch]$ViaScheduledTask
    )

    $explorerExe = Join-Path $env:WINDIR 'explorer.exe'
    if (-not $ViaScheduledTask) {
        Start-Process -FilePath $explorerExe
        return
    }

    $taskName = 'WinIconCacheFixRestartExplorer'
    $created = $false
    try {
        & schtasks.exe /Create /TN $taskName /TR "`"$explorerExe`"" /SC ONCE /ST 23:59 /F | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks /Create 失败 (退出码 $LASTEXITCODE)"
        }
        $created = $true

        & schtasks.exe /Run /TN $taskName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks /Run 失败 (退出码 $LASTEXITCODE)"
        }

        Start-Sleep -Seconds 3
    } finally {
        if ($created) {
            & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
        }
    }
}

$targets = Get-IconCacheTargets -WithThumbCache:$IncludeThumbCache
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $env:TEMP "iconcache-backup-$timestamp"

if ($RefreshOnly) {
    Write-Host '[RefreshOnly] 正在执行无破坏图标刷新 (ie4uinit.exe -show + SHChangeNotify)...'
    Invoke-ShellIconRefresh
    Write-Host '[完成] 已发送系统图标刷新通知，未修改任何文件或重启 explorer.exe。'
    exit 0
}

if ($DryRun) {
    Write-Host '=== DryRun 预览模式（不会修改文件或重启 explorer.exe）==='
    Write-Host ("检测到缓存文件数: {0}" -f $targets.Count)
    foreach ($file in $targets) {
        Write-Host ("  - {0} ({1} bytes)" -f $file.FullName, $file.Length)
    }
    if ($NoBackup) {
        Write-Host '备份设置: 已跳过 (-NoBackup)'
    } else {
        Write-Host ("备份目标: {0}" -f $backupDir)
    }
    $launchMode = if ($UseScheduledTask) { '一次性计划任务 (schtasks)' } else { 'Start-Process' }
    Write-Host ("拟执行动作: 备份缓存 -> 结束 explorer.exe -> 清理上述缓存文件 -> 通过 {0} 拉起 explorer.exe -> 刷新 Shell 图标" -f $launchMode)
    exit 0
}

if ($targets.Count -eq 0) {
    Write-Host '未检测到可清理的图标缓存文件，正在执行常规图标刷新...'
    Invoke-ShellIconRefresh
    Write-Host '[完成] 已发送刷新通知。'
    exit 0
}

if (-not $Force) {
    Write-Host ''
    Write-Host '即将清理并重建 Windows 图标缓存：'
    Write-Host ("  - 涉及文件: {0} 个 ({1})" -f $targets.Count, ($(if ($IncludeThumbCache) { '含缩略图缓存' } else { '保留缩略图缓存' })))
    Write-Host '  - 影响范围: 当前打开的「文件资源管理器」窗口会关闭，桌面与任务栏会闪烁 1-2 秒'
    Write-Host '  - 保留不变: 其他正在运行的软件及任务栏固定项不会受影响'
    if (-not $NoBackup) {
        Write-Host ("  - 备份目录: {0}" -f $backupDir)
    }
    Write-Host ''
    $reply = Read-Host '确认执行吗？输入 Y 继续，其他键取消'
    if ($reply -notmatch '^(?i)y(es)?$') {
        Write-Host '已取消操作，未做任何改动。'
        exit 0
    }
}

if (-not $NoBackup) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    foreach ($file in $targets) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $backupDir $file.Name) -Force
    }
    $backedUpCount = @(Get-ChildItem -LiteralPath $backupDir -File -Force).Count
    if ($backedUpCount -lt $targets.Count) {
        throw "备份校验失败: 预期 $($targets.Count) 个文件，实际仅备份 $backedUpCount 个。"
    }
    Write-Host ("[备份] 已将 {0} 个缓存文件备份到: {1}" -f $backedUpCount, $backupDir)
}

$deleted = New-Object System.Collections.Generic.List[string]
$locked = New-Object System.Collections.Generic.List[string]

try {
    if (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue) {
        Write-Host '[步骤 1/3] 正在短暂停止 explorer.exe 以释放文件锁...'
        & taskkill.exe /f /im explorer.exe | Out-Null

        for ($i = 0; $i -lt 15; $i++) {
            if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
                break
            }
            Start-Sleep -Milliseconds 200
        }
    }

    Write-Host '[步骤 2/3] 正在删除旧图标缓存文件...'
    foreach ($file in $targets) {
        if (Test-Path -LiteralPath $file.FullName) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $deleted.Add($file.Name)
            } catch {
                $locked.Add(("{0}: {1}" -f $file.Name, $_.Exception.Message))
            }
        }
    }
} finally {
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
        Write-Host '[步骤 3/3] 正在重新启动 explorer.exe...'
        Start-ExplorerInteractive -ViaScheduledTask:$UseScheduledTask
    }
}

Start-Sleep -Seconds 3
Invoke-ShellIconRefresh

$explorerProcs = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
$rebuiltFiles = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') -Filter 'iconcache*.db' -File -Force -ErrorAction SilentlyContinue)

Write-Host ''
Write-Host '=== 执行结果 ==='
Write-Host ("已删除缓存: {0} 个 | 仍被锁定: {1} 个" -f $deleted.Count, $locked.Count)
if ($locked.Count -gt 0) {
    Write-Host '被锁定未删除项:'
    foreach ($item in $locked) {
        Write-Host ("  - {0}" -f $item)
    }
}
if ($explorerProcs.Count -gt 0) {
    $pids = ($explorerProcs | ForEach-Object { $_.Id }) -join ', '
    Write-Host ("explorer.exe 状态: 运行中 (PID: {0})" -f $pids)
} else {
    Write-Warning 'explorer.exe 未检测到运行，请按 Ctrl+Shift+Esc 打开任务管理器 -> 运行新任务 -> 输入 explorer.exe 启动。'
}
Write-Host ("重建后的 iconcache*.db 数量: {0} 个" -f $rebuiltFiles.Count)
Write-Host ''
Write-Host '提示: 若个别整理前就一直开启的程序任务栏图标仍为白页，手动关闭并重新打开该程序一次即可；确认正常后可删除临时备份目录。'
