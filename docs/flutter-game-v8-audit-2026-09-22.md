# Flutter game client V8 — audit checkpoint (2026-09-22)

This checkpoint records the verified state before continuing parity work against the original ps0032 `game.exe`.

## Canonical line

- Working continuation branch: `work/flutter-game-client-v8-complete`.
- Base audited branch: `work/flutter-game-client-v7-stable` at `0917c6ffe17061a3b479df14cfbd0e11f0adf47d`.
- The prior V6 multiplayer/PvP divergence was already consolidated into V7 through merge `3e0d3016cc91fb05747c5c5a1674a0021cb62dfd` and follow-up PvP commits.
- V7 already contains post-merge work for remote-player synchronization, PvP targeting/skills, adjacent-sector streaming, authoritative vehicle/mount packets and SMOD collision decoding.

## Last fully green reference gate

GitHub Actions run `35705951644` at commit `1f980db26cebe34b22e7467223a46162c8a5a34c` completed successfully.

Verified by that run:

- Flutter format/analyze/tests.
- Windows release build.
- Bundled localhost ps0032 backend.
- Live Login/World protocol probe.
- Real Windows framebuffer smoke.
- Real ps0032 DATA recovery.
- Original Windows client capture.
- Native-vs-Flutter parity artifacts.

The later V7 commits (streaming, mounts and SMOD collision decoding) were newer than that green run and therefore require a new canonical CI pass.

## Measured visual parity baseline

From artifact `Flutter-Native-Visual-Parity` of run `35705951644`:

| Stage | Pixel similarity | Edge correlation | Luminance correlation |
| --- | ---: | ---: | ---: |
| Faction | 0.91142 | 0.19236 | 0.56427 |
| Character Select | 0.94673 | 0.34766 | 0.72950 |
| Character Create | 0.87709 | 0.16535 | 0.09003 |
| Character Mode | 0.88645 | 0.23389 | 0.23673 |
| World | 0.85391 | 0.26945 | -0.00414 |

Interpretation: the client is already visually close in broad composition, especially character selection, but world rendering/UI/camera/lighting still differs materially from the native client. Pixel similarity alone must not be treated as proof of 1:1 parity.

## Functional state verified in code

The current line contains real implementations for:

- login, faction, character create/select/mode and world entry;
- ps0032 packet framing and authoritative Login/World sessions;
- player movement and live actor synchronization;
- NPCs, mobs, target selection, combat, death/rebirth;
- stats, skills, quickbar and buffs;
- inventory, equipment, item use, warehouse and guild warehouse;
- quests, merchant buy/sell, gatekeepers/teleports and blacksmith lapis operations;
- friends, party, guild, trade, duel and raid;
- remote players and PvP packets/UI;
- map switching and adjacent-sector streaming;
- local/remote mounts plus shared-ride protocol;
- WLD/SVMAP/DG/SMOD rendering and native SMOD collision decoding.

## Gaps that still block a true 100% claim

1. Collision data is decoded but not yet enforced by player movement.
2. DG collision meshes are still skipped during parsing.
3. World streaming reloads a local 128 m sector rather than maintaining a persistent multi-sector scene/cache.
4. World object loading is capped and rebuilt per sector; this can omit native scene density and costs unnecessary reload work.
5. Full original audio routing (map music, ambient zones, UI, NPC/mob and every skill SFX) is not complete.
6. Skill coverage still needs exhaustive target modes, AoE/cast/status/cooldown behavior and multiplayer validation.
7. Every specialized NPC/system exposed by the native client still needs a packet/UI inventory and proof, not just generic NPC interaction.
8. Multi-client E2E must cover Friends/Party/Guild/Trade/Duel/Raid/PvP/Mounts under reconnect and failure cases.
9. Visual parity still needs camera/FOV, UI geometry, fonts, minimap, quest/dialog composition, lighting/fog/sky and per-map comparison.
10. CI previously watched only `work/flutter-game-client-v1`; this branch updates the gate to validate the actual canonical work lines.

## Definition of done

A feature is not considered complete merely because a widget or packet method exists. Closure requires, where applicable:

- authoritative protocol/state integration;
- original DATA/resource integration;
- deterministic unit/protocol tests;
- real Windows execution;
- multi-client E2E for multiplayer systems;
- native `game.exe` comparison for behavior and presentation;
- no regression against the parity baseline.

The target is two compatible presentation profiles: **Classic parity** for native behavior/layout and **Enhanced** for optional improvements that must not destroy protocol/data compatibility.
