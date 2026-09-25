# R24 — appearance and registered equipment follow-up

## Changes implemented

- Full schema-3 Studio appearance saves exact MLT/ITM/MON keys, armor, weapon,
  shield, wings, mount, per-axis offsets, Euler rotations, scale, mirrors,
  attachment bone, rider profile and automatic wing motion.
- Referenced DATA assets receive SHA-256 fingerprints. Loading verifies schema,
  typed fields, record resolution and all declared resources before application;
  a late renderer failure attempts to restore the previous appearance. A failed
  restore is reported rather than hidden. Loading a look does not teleport.
- Existing schema-2 body-only saves remain loadable.
- A single exclusive resources/registered-items mode is used across armor,
  weapons, wings and mounts. Registered mode uses real Type:TypeId identities,
  class/faction restrictions, and Image -> MLT/ITM/MON references. Ambiguous
  resources are not silently collapsed to the first matching record.
- The armor object dialog distinguishes repair-existing from explicit-template
  creation. It validates Spanish Windows-1252 text, preserves original fields,
  reopens both tables, and exports a new COPIAR_EN_DATA patch directory. It never
  writes half a transaction to active DATA/SPK. Unknown MLT references refuse
  publication. It does not create arbitrary MLT rows or item icon atlases.
- New native-offline-oriented TypeId values are bounded to 1..255 because the
  inspected bundled backend 0.1.2 uses byte IDs. Existing larger IDs are readable.
- The Windows wing assertion now evaluates local offsets in the native rotation
  and animated bone frame, rather than assuming raw WING_UP_DOWN is world Y.

## Real supplied DATA: Conjunto 016

Read from DATA_Español/binarysdata, not the separate root DBItemData. Under Human
Fighter restrictions, these five rendered resources already have objects:

| Piece | Image (MLT ordinal) | Type:TypeId | Icon | Level |
|---|---:|---|---:|---:|
| upper016 | 42 | 73:6 | 47 | 80 |
| lower016 | 41 | 74:6 | 46 | 80 |
| hand016 | 41 | 76:6 | 46 | 80 |
| foot016 | 41 | 77:6 | 46 | 80 |
| helmet016 | 52 | 72:232 | 63 | 80 |

Their supplied Spanish names are question marks, not missing object rows.
There are 28,142 numeric rows and 28,142 Spanish text rows. The original numeric
SEED envelope has a stale CRC (stored 1625578045 vs calculated 2693759567). This
is a warning about that supplied legacy file, not proof of SPK authentication.
No replacement Spanish name is invented or silently applied.

## Still open (not disguised as completed)

1. Native game.exe flight state/animation hooks, runtime input/ground-contact QA,
   and a native --appearance consumer. The full snapshot is a Studio contract.
2. Exact native icon-atlas mapping for all modern item types; new thumbnail
   generation/atlas insertion. The dialog currently edits the native Icon index.
3. Batch set-stat (DBSetItemData) authoring and synchronized server database
   import. Current publication edits a selected armor object/data-text pair.
4. Create/repair dialogs extended to every non-armor type, after proving their
   native table/rider-family/icon semantics. Registered selection exists already.
5. Native writing of scale/mirror, absent from WingPosition's original fields.
6. DATA.SPK payload AES-GCM key authentication and 50,135-resource audit/repack.

## Package policy

Bundle the byte-identical verified compact Flight V3 runtime under
Extras/FlightV3/Shaiya_Studio_FlightV3_Runtime.zip so Studio loads it on DATA
connection. Body humf ANI belong under Character/Human/ANI, never under
Character/Wing/ani (different skeletons). A normal folder layout alone does not
teach an unmodified native executable to select new animation states.

Do not rename the previous game.exe to imply a new modified client. Do not call
this release 100% accepted before native visual QA and the open gates above.
