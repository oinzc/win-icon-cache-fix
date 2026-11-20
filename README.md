# win-icon-cache-fix

> A safe, one-click PowerShell tool to backup and rebuild the Windows 10/11 icon cache when taskbar or desktop icons turn into blank white sheets.

一键备份并重建 Windows 10/11 图标缓存，解决桌面图标（`.lnk`）整理或软件更新后任务栏/桌面图标变成空白白页图标的问题。

## 适用场景

- 整理桌面，把多个 `.lnk` 桌面图标批量移入子文件夹后，任务栏或桌面部分应用图标变成空白白页。
- 软件更新、重装或路径变更后，任务栏固定图标或打开窗口的图标显示异常。
- 普通右键刷新或重启应用仍无法恢复的图标缓存损坏。

## 为什么会这样

Windows 会将桌面和任务栏图标缓存在以下位置，并且 `explorer.exe` 在运行期间会一直占用锁定其中的 `iconcache_*.db`：

- `%LOCALAPPDATA%\IconCache.db`
- `%LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache_*.db`

当原桌面图标路径变化、任务栏固定状态或进程启动句柄发生错位时，缓存中会记下“找不到图标”的回退白页图标。仅调用常规刷新往往清不掉被资源管理器锁住的陈旧数据库，需要**先备份、短暂结束 `explorer.exe` 删除旧缓存、再重启 `explorer.exe` 自动重建**。

## 快速使用

### 方式一：双击批处理（推荐）

直接双击运行 [`fix-icon-cache.bat`](fix-icon-cache.bat)（无需管理员权限，自动绕过当前进程的 PowerShell 执行策略限制），阅读影响说明后输入 `Y` 确认即可。

### 方式二：PowerShell 命令行

```powershell
# 预览将要处理的缓存文件，不做任何改动（推荐先跑一次确认）
.\fix-icon-cache.ps1 -DryRun

# 交互式备份、清理并重建图标缓存（默认保留 thumbcache_*.db 缩略图缓存）
.\fix-icon-cache.ps1
```

### 参数说明

| 参数 | 说明 |
| --- | --- |
| （无参数） | 默认模式：提示影响并确认后，备份旧缓存 → 重启 `explorer.exe` 清理重建 → 刷新图标 |
| `-DryRun` | 仅预览检测到的缓存文件与拟执行动作，不停止 `explorer.exe`、不删除文件 |
| `-RefreshOnly` | 仅发送 `ie4uinit.exe -show` 与 `SHChangeNotify` 刷新通知，不重启资源管理器 |
| `-IncludeThumbCache` | 一并备份并清理 `thumbcache_*.db` 缩略图缓存（默认保留不删） |
| `-NoBackup` | 跳过备份步骤直接清理 |
| `-Force` | 跳过交互式 `Y/N` 确认，适合脚本或自动化调用 |
| `-UseScheduledTask` | 通过一次性交互式计划任务拉起 `explorer.exe` 并立即删除临时任务，适合会回收子进程的终端或自动化包装环境 |

## 安全机制

- **默认先备份**：清理前自动把所有命中的缓存文件备份到 `%TEMP%\iconcache-backup-<时间戳>`，并校验备份文件数（含隐藏文件）。
- **只动图标缓存**：默认保留 `thumbcache_*.db`（图片/视频缩略图缓存）不动，减少不必要的重新生成耗时。
- **确保恢复桌面**：清理过程放在 `try / finally` 中执行，即使删除阶段有文件被其他进程锁定，也会在 `finally` 中自动重新拉起 `explorer.exe`。
- **不关闭业务软件**：仅短暂重启文件资源管理器（桌面与任务栏闪烁 1-2 秒，已打开的文件资源管理器窗口会关闭），不会强关浏览器、IDE、聊天工具等任何其他应用。

## 常见问题

1. **重建完成后，个别一直开着的程序（如 IDE、浏览器）任务栏图标还是白页怎么办？**  
   如果该程序在移动 `.lnk` 文件之前就已经启动且一直未关闭，它的窗口进程可能仍绑定着旧桌面 `.lnk` 的启动句柄。手动关闭并重新打开该程序一次（或右键任务栏图标取消固定再重新固定）即可恢复。
2. **整理桌面时要注意什么？**  
   移动前留意区分 `.lnk` 链接文件和 `.exe` 程序本体：如果不小心把自带开机自启的绿色版 `.exe` 本体一起移进了子文件夹，记得同步更新对应的开机自启路径或改用链接文件，避免下次开机自启失效。

## License

[MIT](LICENSE)
