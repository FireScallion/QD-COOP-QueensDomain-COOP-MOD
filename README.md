# Queen’s Domain COOP



**English** | [简体中文](README.zh-CN.md)

Queen’s Domain COOP adds cooperative play to Queen’s Domain. Version 1.2.7 supports 2–4 players over LAN or through Steam friends.

After the one-time installation described in [INSTALL.md](INSTALL.md), launch normally through Steam or the original launcher. Multiplayer provides separate Steam hosting, Steam joining, LAN hosting and LAN joining entries. Steam play requires each participant to own and run the Steam game.

You can play on the same local network or connect through a virtual LAN tool such as **Radmin VPN**.

1.2.7 adds recovery for a stalled crushing reset after three seconds. Crushing damage and downed states remain intact; recovery waits while menus, teleportation or cutscenes are active.

## How to Play Co-op

**Hosting adds extra world simulation, enemy AI, and synchronization overhead. We recommend that the player with the more powerful PC hosts the game.**

1. **Install on every PC.** Use matching game and mod versions. Extract into the game root and run `Install.cmd` with the game closed. Remove obsolete custom Steam launch options. Uninstall the native-DLL QDCoop branch first; do not load both branches together.
2. **Host a room.** Select Steam hosting or LAN hosting, choose a capacity of 2–4, then select a character save or create a character. LAN defaults to UDP port `47771`. The room opens after entering the world.
3. **Invite friends.** In a Steam room, choose **Invite partner** below Continue in the pause menu. The new in-game friends panel follows the original menu style and supports names, status, avatars when available, and paging.
4. **Join through Steam.** Choose the Steam friends entry and select an available room from the in-game list, or accept a Steam invitation. Then select your own save. Save before leaving an existing game to join another room.
5. **Join over LAN instead.** Choose **Multiplayer → Join LAN game** and enter the host’s IPv4 address and port. Different networks can still use **Radmin VPN**. Use the host’s LAN/Radmin IP, not your own address or `127.0.0.1`. See the [Radmin VPN guide](https://www.radmin-vpn.com/help/). Windows Firewall must allow `QDCoopBridge.exe`; LAN uses UDP `47771` by default.

Steam multi-account joining, invitations, reconnects and Internet direct/relay routing still require real Steam playtesting. Four local game instances have passed targeted LAN checks; this is not a claim of complete four-player campaign or visual coverage.

Capacity is **one host and up to three guests**. Version 1.2.7 uses the original save directory; back up your saves before testing.

## Player appearance

The Multiplayer menu includes five appearances: **Prince, Arjaot, Ippibi, Ujji, and Imba**. Use the arrows above the preview to browse, then press **Select** to equip an appearance. The button disappears for the selected model. Your selection is remembered when you reopen the menu or restart the game. Both the host and the guest can choose an appearance.

The four soldier appearances reuse the existing full-body animation system: Arjaot, Ippibi, and Ujji wear helmet 00; Imba wears the closed helmet 01. This changes the third-person appearance seen by your teammate. First-person arms, character statistics, and collision remain those of the original character.

## Co-op and Progression

The host’s world determines shared progression, including mechanisms, doors, destructible shortcuts, boss phases, and passages unlocked after boss fights. Special boss dialogue and cutscenes are controlled by the host, as is in-game teleportation. Book-placement puzzles are operated by the host, with the results synchronized to the joining player.

The joining player keeps their own character, equipment, experience, and personal pickup progress. Items placed in the original game world can be collected independently by each player. Both players can also receive their own enemy drops according to the original game’s drop rules. After saving, the guest can host with that character using the saved shared world progress and their own safe position.

Version 1.2.7 uses the original game save directory for both single-player and co-op. A backup is created under `QDCoop-Direct/Backups` at startup; old isolated saves are not imported automatically. When a player saves, all connected players save the shared world progress and their respective character states.

## Downed Players and Revival

When a player is downed, their teammate can face them and **hold E to revive them**. Revival progress uses the original blue charge bar. Releasing E interrupts the revival.

- If a healing item is selected, a successful revival consumes one item and restores the amount of health provided by that item.
- If no healing item is selected, the teammate is revived with 1 HP without consuming an item.
- If all players are downed, the most recent complete shared save is loaded automatically, restoring the last saved progress.

## Synchronization and Animation

To bring co-op to a game originally designed for single-player, the mod adds synchronization for players, enemies, and world interactions.

**Third-Person Player Animation**

Using the original character, weapon, and animation assets alongside newly created and adapted animations, the mod adds a full set of third-person actions: walking, running, jumping, looking up and down, holding weapons, charging attacks, attacking, and falling into a downed pose. Different weapons retain their distinctive motions, with synchronized ranged projectiles, weapon effects, and sound effects.

Where possible, animations play locally on each machine, with action states and playback progress synchronized between players. This reduces the overhead of continuously transferring skeletal poses. Movement uses interpolation and smoothing to soften the gaps between network updates.

**Enemies and Combat**

Enemy positions, orientations, animations, health, deaths, attack effects, and sounds are synchronized. Enemies can pursue and attack players on either side of the connection. Target selection considers distance, recent damage, and visibility, while limiting frequent target switching when players take turns attacking.

Enemy presentation reuses the original animations and effects wherever possible, playing them continuously on each machine. Combat outcomes are coordinated by the host, with the joining player’s attacks contributing to the same fight.

**How Enemy Aggro Works**

The host evaluates co-op enemy targets using all players’ positions, recent actual damage, and visibility.

- **Distance and damage both matter.** Nearby players attract more attention, while dealing more actual HP damage raises a player’s threat score. Damage is tracked over a rolling window of roughly 3 seconds and gradually loses weight. Rapid throwing-knife hits therefore gain no extra advantage merely from hit count, and an earlier burst of damage does not lock aggro indefinitely.
- **Sight and cover matter.** Players within an approximately 120° forward cone and a clear line of sight receive a visibility bonus. Attacking from behind can also draw attention, but does not give the enemy vision through walls. When a target briefly moves behind cover, the enemy can retain roughly 1 second of memory and pursue the last visible position. Treasure lizards retain their native fleeing behavior instead of following this chase-memory rule.
- **Damage can decisively transfer aggro.** If another eligible, unobstructed player has dealt at least 1.5 times the current target’s recent effective damage, they take priority. Damage continues to decay over the same 3-second window and targets are reevaluated. Otherwise, score-based switching retains its usual meaningful-advantage and roughly 1.5-second hold rules. A committed attack or recovery may briefly delay a switch, for at most about 1.2 seconds, to avoid abruptly turning mid-swing.
- **Every player can draw aggro.** A host-side proxy represents the joining player for pursuit, hit detection, and damage, allowing enemies to actually attack them. Being downed, dying, or leaving the effective range also influences target selection. Some special attacks with targets dictated by story scripts still follow their original behavior.

**World Interactions**

Alongside synchronizing mechanisms and world states, the mod aims to preserve the animations and sounds of doors, chests, hidden passages, and similar interactions. Synchronization also covers boss phase transitions, death resolution, barrier removal, and restoring player control after cutscenes.

## Changes for Co-op

During multiplayer, the inventory, bestiary, pause menu, weapon evolution, and similar features no longer pause the entire world. Other players and enemies continue to act while these interfaces are open. Some original scripted sequences still temporarily restrict the controls of the player watching them.

To balance smooth gameplay with synchronization, we have moved inter-process communication to shared memory to reduce frequent file reads and writes; optimized object lookups, enemy state collection, effect updates, and animation processing; and moved many remote player actions to local animation playback. By design, local camera control and movement do not wait for network packets. The network primarily carries state, actions, and interaction results.

## Current Status

Currently supports **one host and up to three guests**. The mod is still being improved, and complex scenes, special enemies, and network conditions may affect synchronization and performance. All players should use the same version and back up their co-op saves before updating.

## Development Assistance and Thanks

**GPT ASTRA — AI development assistance.** Guided by the author’s requirements, gameplay decisions, and in-game testing feedback, GPT ASTRA contributed to co-op architecture and synchronization design, code implementation and review, third-person animation adaptation and tooling, performance analysis, troubleshooting, and documentation. The mod also benefits from players who test builds, reproduce issues, and share diagnostic logs.

Hotfix8 candidate reconciles library gem locks from saved beacon receipts after guest requests and while hosting or playing solo. Old-save recovery requires the beacon area to be loaded and its saved receipt to remain present. Offline logic checks passed. In-game validation is pending.
