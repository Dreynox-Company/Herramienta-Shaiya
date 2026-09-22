# ps0032 parity gap audit — 2026-09-22

Source comparison: current Flutter `PsPacketType` vs. the public EP8/ps0032 `Imgeneus.Network.Packets.PacketType` contract.

## Coverage checkpoint

- Upstream packet values audited: **366**
- Packet values already declared by Flutter client: **173**
- Packet values not yet declared: **193**
- Of the 193 gaps, **33 are GM-only commands**. Those are not required for ordinary player parity, but remain part of a literal full-client audit.
- The missing player-facing values are concentrated in advanced combat/targeting, personal shop, market, linking/crafting, guild-house/GRB, teleport utilities, dyeing, party search, bank, Chaotic Square and miscellaneous account/kill-status systems.

The count is a protocol-surface audit, not a completion percentage. A declared opcode is not considered implemented until packet layout, authoritative state, UI/action path and tests exist.

## Missing player-facing surfaces by upstream category

| Area | Missing packet values |
| --- | ---: |
| Character | 3 |
| Common session/character actions | 5 |
| Game/core | 7 |
| Map | 6 |
| Attack | 3 |
| Mobs | 4 |
| Stats / auto-stats | 4 |
| Target / target buffs | 7 |
| PvP / casting / range skills | 12 |
| Obelisk | 2 |
| Inventory expiration | 2 |
| Party additions | 2 |
| Summon / party call | 4 |
| Player chat additions | 4 non-admin |
| Personal shop | 14 |
| Bless | 3 |
| Reset skills | 1 |
| Party search | 2 |
| Linking / enchant / compose | 10 |
| Guild House / GRB | 10 |
| Teleport utilities | 5 |
| Dyeing | 3 |
| Experience / leveling events | 3 |
| Bank | 2 |
| Chaotic Square | 4 |
| Market | 17 |
| Account points | 1 |
| Kill status / rewards | 3 |
| Infinite Sanctuary | 1 |

## Immediate closure order

1. **Combat/target parity** — target buffs, casting, range skills, skill-keep/mirror, character/mob recovery/speed.
2. **World event parity** — dropped map items, day state, NPC attacks, experience/level-up, money and item expiration.
3. **Character/session parity** — name check, logout/quit, rename/restore, inventory sort, reset skills/auto-stats.
4. **Blacksmith/linking parity** — enchant, compose/remake/consider, cloak operations, rune synthesis and absolute compose.
5. **Guild House / GRB** — Etin, guild NPCs/upgrades, house buy/keep, GRB points/notices.
6. **Personal shop + Market** — complete seller/buyer flows and auction/search/favorites.
7. **Teleport / summon / party search** — saved positions, preloaded town/area, battleground, party call, party finder.
8. **Dye / bank / Chaotic Square / account / kill rewards / sanctuary**.
9. **GM/admin packets** only after ordinary game parity is closed unless needed by QA tooling.

## Definition of implemented

Each subsystem requires:

- exact packet layouts validated against ps0032/server source or live captures;
- encode/decode tests;
- authoritative state handling in the Flutter runtime;
- an original-style UI/action path where the native client exposes one;
- real two-client E2E where the feature is multiplayer;
- no regression in Windows build, live protocol gate or visual-parity jobs.
