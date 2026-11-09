# QD COOP 1.17.3

## English

1. Close the game. Extract this package into the game root containing `QueensDomain.exe`, `Engine`, and `QueensDomain`.
2. Run `Install.cmd` once. It deploys the bundled UE4SS, mod scripts and four mod Paks, merges required settings, and backs up replaced files. Existing mod folders and their entries are preserved. Do not install while the game is running.
3. Clear any old Steam launch option pointing at `QDCoopLauncher.exe` or `Launch-QDCoop.cmd`.
4. Start the original game launcher or use Steam's Play button. Use Multiplayer to host or join by IPv4 and port. Both players must use 1.17.3 with matching game archives.

No separate co-op launcher is needed. A hidden session supervisor follows the game process; the network bridge starts when a room is requested and stops when you leave or the game exits. The mod does not change renderer, resolution, or launch arguments.

**Saves are no longer isolated.** Single-player and multiplayer use the game's original save directory, normally `%LOCALAPPDATA%/QueensDomain/Saved/SaveGames`. Existing saves are backed up at startup under `QDCoop-Direct/Backups`. Co-op progress can change these saves. The old `QDCoop-Direct/Local/host/profile/Saved/SaveGames` files are retained but are not automatically copied into the original directory. Copy only a deliberately chosen save while the game is closed if you want to continue an old co-op character. Keep your backup.

Run `Uninstall.cmd` with the game closed to restore backed-up files and remove unchanged files installed by this version. Files modified after installation are kept with a warning. Saves and `QDCoop-Direct` data are not removed. Keep `InstallBackup` until uninstall is complete. If the installer detects an unfamiliar `dwmapi.dll`, it stops instead of replacing another loader.

Troubleshooting: `QDCoop-Direct/Local/native/bootstrap.log`, `bridge-stderr.txt`, and `ipc/`; UE4SS log: `QueensDomain/Binaries/Win64/ue4ss/UE4SS.log`. One game process per installation may use this co-op runtime at a time. Separate game copies are required for same-PC dual-instance tests.

The original launcher and room connection were checked using disposable game copies and save profiles. Steam-specific overlay, achievements, Cloud behavior and DRM remain unverified. This release still uses LAN/IP transport, not Steam invitations.

## 简体中文

1. 关闭游戏，将完整包解压到包含 `QueensDomain.exe`、`Engine`、`QueensDomain` 的游戏根目录。
2. 运行一次 `Install.cmd`。安装会部署 UE4SS、Mod 脚本和四个资源包，备份被替换文件，并合并必要设置；保留其他 Mod 的目录与启用项。不要在游戏运行时安装。
3. 如果曾设置 Steam 启动项指向 `QDCoopLauncher.exe` 或 `Launch-QDCoop.cmd`，清空该启动项。
4. 以后直接使用原版启动器或 Steam 的“开始”按钮，通过多人菜单主持或加入。双方需要使用 1.17.3 和匹配的游戏资源版本。

不再需要独立联机启动器。隐藏的会话管理进程跟随游戏运行；只有发起房间请求才启动网络后台，退房或游戏退出后关闭。Mod 不设置渲染器、分辨率或游戏启动参数。

**本版不再隔离存档。** 单人和多人共用原版存档目录，通常为 `%LOCALAPPDATA%/QueensDomain/Saved/SaveGames`。启动时自动将现有存档备份到 `QDCoop-Direct/Backups`，联机进度可能修改原版存档。旧版 `QDCoop-Direct/Local/host/profile/Saved/SaveGames` 中的隔离存档会保留，但不会自动导入。若要继续旧联机角色，请在关闭游戏后自行选择需要的存档复制到原版目录，并保留备份。

关闭游戏后运行 `Uninstall.cmd`，可恢复安装前文件并移除本版新增且未被修改的文件。安装后另行修改的文件会保留并提示；存档与 `QDCoop-Direct` 数据不会删除。卸载完成前请保留 `InstallBackup`。若检测到未知的 `dwmapi.dll`，安装器会停止，避免覆盖其他加载器。

日志在 `QDCoop-Direct/Local/native/bootstrap.log`、`bridge-stderr.txt` 和 `ipc/` 中。UE4SS 日志在 `QueensDomain/Binaries/Win64/ue4ss/UE4SS.log`。同一个安装目录同时只支持一个游戏进程使用联机功能；本机双开需分别使用两份游戏目录。

已使用复制的游戏和测试存档验证原版启动器入口及房间连接；Steam 覆盖层、成就、云存档行为及 DRM 兼容仍待 Steam 正版实测。本版仍通过局域网 IP 连接，不提供 Steam 邀请功能。
