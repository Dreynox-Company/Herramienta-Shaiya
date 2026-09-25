# R24 — Native wing transform and responsive flight

## Evidence and reproduction

Inspected the actual ps0032 executable from the owner's offline 0.1.2 package.
SHA-256: `509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`.
The source baseline is `ac6c1037fc2b04868fb3b9caa1172397334a7123` (Studio 0.6.22).
No generic 180-degree correction was written to the owner's XML or models.

- `0x497260`: opens `data/ExcelXml/WingPosition.xml`; imports rows by
  FAMILY/JOB/SEX. Row size 28 bytes: bone; integer X/Y/Z angles; three floats.
- `0x4974f0`: selects `(FAMILY*6+JOB)*2+SEX` and copies a 28-byte profile.
- `0x4665b0`: selects the BONE_IDX bone matrix (default 4 if no profile).
- `0x525440`: composes the native wing attachment. X, Y, Z rotations call
  `0x71202c`, `0x7120ce`, `0x712171`, respectively.
- `0x5256b8..0x525910`: up direction (0,1,0), front (0,0,-1), lateral is
  front cross up, therefore (1,0,0). Offsets are translations in those axes.
- `0x52592a..0x5259ba`: row-vector matrix products are
  `Tfront*Tup*Tleft*Rx*Ry*Rz*bone*world`.
- The column-vector renderer must therefore use
  `world*bone*Rz*Ry*Rx*T(left,up,-front)`.

The old renderer used `world*bone*T(left,up,front)*Rx*Ry*Rz`, a distinct
operation. For Human 170/0/90, the unit X direction pointed downward (Y=-.9848)
in the old local transform and upward (Y=1) in the native composition. This
matches the direction of the reported inversion. Whole-scene screenshot parity
still requires a real Windows session with the same outfit, bone pose and wing.

The original reader uses integer angles. Fractional degrees remain useful as
Studio preview values but native export must warn/reject or explicitly quantize;
never promise fractional-angle parity in the original client.

## Flight

Two independent gates caused movement to wait for visual takeoff: a flight
transition counted as combat lock, and translation required identity with the
final movement clip. Both conditions are addressed. Interactive presentation
budgets are 200 ms takeoff, 160 ms landing, 90 ms hover/cruise, 140 ms combat
contact presentation. These are explicit design targets, not measured native
client timings. Attacks, impact markers and cooldowns keep original timing.

Held movement may redirect a presentation endpoint without restarting it.
Presentation time scaling is local to the transition and resets on a new clip;
overshoot is retained. Inspector demonstration sequences retain original timing.

Tests cover the matrix against independent scalar native operations, offset sign,
separate preview mirror, and real StudioScene V3 transition control at 30/60/144 Hz.
Synthetic tests are not evidence that the original game.exe has new flight logic.
