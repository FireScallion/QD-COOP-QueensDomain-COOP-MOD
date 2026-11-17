# QD COOP 1.2.7

## English

1. Close the game. Extract this package into the game root containing `QueensDomain.exe`, `Engine`, and `QueensDomain`.
2. Run `Install.cmd` once. It deploys the bundled UE4SS, mod scripts and five mod Paks, merges required settings, and backs up replaced files. Existing mod folders and their entries are preserved. Do not install while the game is running.
3. Clear any old Steam launch option pointing at `QDCoopLauncher.exe` or `Launch-QDCoop.cmd`.
4. For Steam friends play, install into your Steam copy and use Steam's Play button. All players must own the game, be online in Steam, enable Steam Overlay, and use QD COOP 1.2.7 . Host a save, then use **Invite partner** under Continue. **Join friends** opens the in-game Steam friends panel; **Join LAN game** retains IPv4/port connections.

No separate co-op launcher is needed. A hidden session supervisor follows the game process. The gameplay bridge runs during a room session; the Steam service stays available at the title screen to receive invitations. Both close with the game. The mod does not change renderer, resolution, or launch arguments. It never replaces or bundles `steam_api64.dll`; Steam support uses the original Valve-signed API from your game installation. LAN remains usable when Steam is unavailable.

**Saves are no longer isolated.** Single-player and multiplayer use the game's original save directory, normally `%LOCALAPPDATA%/QueensDomain/Saved/SaveGames`. Existing saves are backed up at startup under `QDCoop-Direct/Backups`. Co-op progress can change these saves. The old `QDCoop-Direct/Local/host/profile/Saved/SaveGames` files are retained but are not automatically copied into the original directory. Copy only a deliberately chosen save while the game is closed if you want to continue an old co-op character. Keep your backup.

Run `Uninstall.cmd` with the game closed to remove QDCoop scripts, runtime and its five Paks, including modified QDCoop-owned files. UE4SS, unrelated mods, saves, backups and user data remain. Uninstall does not restore an older QDCoop version. There is no game executable version allowlist; unknown loaders and an installed native-DLL QDCoop branch still require resolving the loader conflict before installation. Uninstall the native branch with its own uninstaller first.

Troubleshooting: `QDCoop-Direct/Local/native/bootstrap.log`, `bridge-stderr.txt`, and `ipc/`; UE4SS log: `QueensDomain/Binaries/Win64/ue4ss/UE4SS.log`. One game process per installation may use this co-op runtime at a time. Separate game copies are required for same-PC dual-instance tests.

Version 1.2.7 supports up to four players. Use the same mod version as the host.

## 简体中文

1. 关闭游戏，将完整包解压到包含 `QueensDomain.exe`、`Engine`、`QueensDomain` 的游戏根目录。
2. 运行一次 `Install.cmd`。安装会部署 UE4SS、Mod 脚本和五个资源包，备份被替换文件，并合并必要设置；保留其他 Mod 的目录与启用项。不要在游戏运行时安装。
3. 如果曾设置 Steam 启动项指向 `QDCoopLauncher.exe` 或 `Launch-QDCoop.cmd`，清空该启动项。
4. 使用 Steam 好友联机时，安装到 Steam 版游戏目录，再使用 Steam 的“开始”按钮。各玩家需拥有游戏、登录 Steam、启用游戏内覆盖界面，并使用 1.2.7 。房主选择存档进入世界后，在 ESC 的「继续」下方点击「邀请伙伴」；「加入好友」打开游戏内 Steam 好友面板，「加入局域网游戏」保留 IP 与端口连接。

不再需要独立联机启动器。隐藏的会话管理进程跟随游戏运行；游戏同步后台仅在联机会话中运行，Steam 服务则在主菜单保持待命以接收加入请求，两者都随游戏退出。Mod 不设置渲染器、分辨率或游戏启动参数，也不附带或替换 `steam_api64.dll`，而是调用本游戏目录中带 Valve 签名的原始 Steam API。Steam 不可用时仍能使用局域网。

**本版不再隔离存档。** 单人和多人共用原版存档目录，通常为 `%LOCALAPPDATA%/QueensDomain/Saved/SaveGames`。启动时自动将现有存档备份到 `QDCoop-Direct/Backups`，联机进度可能修改原版存档。旧版 `QDCoop-Direct/Local/host/profile/Saved/SaveGames` 中的隔离存档会保留，但不会自动导入。若要继续旧联机角色，请在关闭游戏后自行选择需要的存档复制到原版目录，并保留备份。

关闭游戏后运行 `Uninstall.cmd`，会移除 QDCoop 的脚本、后台程序和五个专属资源包，包括被修改过的本 Mod 文件；保留 UE4SS、其他 Mod、存档、备份和用户数据，不恢复旧版 QDCoop。安装没有游戏 EXE 版本白名单；未知加载器和仍在安装中的原生 DLL 分支仍需先解决冲突。请先使用原生分支对应的卸载方式移除该分支。

日志在 `QDCoop-Direct/Local/native/bootstrap.log`、`bridge-stderr.txt` 和 `ipc/` 中。UE4SS 日志在 `QueensDomain/Binaries/Win64/ue4ss/UE4SS.log`。同一个安装目录同时只支持一个游戏进程使用联机功能；本机双开需分别使用两份游戏目录。

1.2.7 最多支持四人。加入前请确认双方使用相同版本。


Installer hotfix: Uninstall.cmd removes the deployed QDCoop mod and PAKs, while keeping the installation payload in QDCoop-Direct for reinstalling. If an older uninstaller already removed that payload, extract this complete ZIP again before running Install.cmd.
安装修复：卸载后保留 QDCoop-Direct 安装源文件，便于再次安装。旧卸载器已删除源文件的用户，请重新解压此完整包后运行 Install.cmd。
