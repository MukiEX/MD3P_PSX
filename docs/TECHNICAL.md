# Magical Drop III PS1 Paddle Edition: Technical Breakdown

Oct 18, 2026

The Paddle Edition patches all six language EXEs and the language selector of Magical Drop III (Europe, SLES-02964) so the clown is driven by a virtual paddle from a PlayStation Mouse, NeGcon, Namco Volume or a JP3-style spinner on the d-pad, in PAL and 60 Hz NTSC builds, with or without the language screen.

## At a glance

```
PS Mouse (0x12) ─┐
NeGcon   (0x23) ─┤                      ┌─> game held/pressed words (menus, card select, name entry)
Volume   (0x23) ─┼─> InitPAD raw bufs ─> pad_one ─┤
JP3 on d-pad    ─┘     (VBlank)        (per port) └─> paddle tick ─> clown hook 0x8003575C (in play)
```

All four controllers share one driver and one reader; the game only ever sees a normal button word, and the patch's own tick turns the rest into paddle position and menu taps.

## Disc and executables

The disc is one MODE2/2352 track; the patch rewrites seven files in place without moving anything, so only changed sectors get new EDC/ECC.

| Item | Value |
| --- | --- |
| Source image | Redump BIN, 193,750 sectors, 455,700,000 bytes, CRC32 FE561E70 |
| Boot file | SLES\_029.64: language selector (PS-X EXE, load address 0x80010000) |
| Game EXEs | MD3EN / FR / GE / IT / SP / NL.EXE, 1,030,144 bytes each (image 0xFB000), LBAs 59 / 562 / 1065 / 1568 / 2071 / 2574 |
| EXE table in the selector | 0x8001F4A8, six pointers to `cdrom:\MD3xx.EXE;1` strings |
| Language call | 0x80011660 runs the flag screen and returns the index; the caller then loads that EXE |
| Patch scope | All six EXEs get identical code; addresses differ by a few bytes and are found by signature |

Every address in this doc is for MD3EN.EXE unless it says otherwise.

## Finding room for the code

The game has no spare RAM, so about 6 KB of code and data live inside each EXE, split into 20 chunks placed in library functions nothing can call plus the tail of the EXE image.

- **Unreachable code**: build.py walks the call graph from the entry point and from every pointer-looking word and lui/addiu pair in the image. Runs never reached, starting at a function prologue (`addiu sp, sp, -n`) and at least 0x40 bytes long, are free. Recorded coverage from real play confirmed none of them ever ran.
- **EXE tail**: 0x8010A8E0 to 0x8010B000 sits after the BSS but inside the file image.
- **Heap**: the game never allocates, but InitHeap wrote its header over that tail. The heap start (0x80063684) now points at 0x8010B000.
- **Packing**: chunks go best-fit, largest first. If that fails, a backtracking search tries each hole per chunk. Total free space was never the limit (8.5 to 9.8 KB per language); fragmentation was. Splitting big chunks below the size of the ninth-largest hole fixed every failure.
- **Chunks**: marked `;@chunk name` in the asm. A chunk is assembled once to measure it, then placed with `.org`. Local `@@` labels end at a global label, so a branch into another chunk becomes a local trampoline `j target`. A chunk entered by `jal` returns a status in v1 (0 done, 1 continue as mouse, 2 failed read) instead of jumping into its caller's labels.
- **Per-language addresses**: hook sites are found by masked signatures taken from MD3EN (immediates and jump targets masked out). The original instructions at each site are checked before writing, so a wrong EXE is refused.

## Pad driver replacement

The game's BIOS B(15h) pad driver returns only a digital button word, so PadInit now starts the library driver with raw buffers and PadRead rebuilds the same word from them.

- **Init** (PadInit tail): `InitPAD(raw1, 0x22, raw2, 0x22)` at 0x80063D4C, `StartPAD()` at 0x80063DDC, `ChangeClearPad(0)`. The driver fills both buffers every VBlank.
- **Raw buffer**: byte 0 status (0 = good), byte 1 ID (0x41 digital, 0x73 analog, 0x12 mouse, 0x23 NeGcon/Volume), then button bytes (active low) and analog bytes.
- **PadRead** (0x8006CBAC) returns `p1 | p2 << 16`, active high, in the format every screen already expects. Each port goes through `pad_one`, which dispatches on the ID.
- **Stale buffers**: after each read the buffer's ID byte is cleared to 0. The driver rewrites it with every transfer, so a buffer still reading 0 is old data and returns the last word again.
- **Failed reads**: a non-zero status repeats the port's last word and keeps all detection state. Only 30 failed reads in a row count as unplugged.
- **Read rate**: the game reads once per frame in play (fewer on some screens). The language selector reads every other frame.
- **Selector**: SLES\_029.64 keeps its own driver; the hook at 0x800136B4 wraps its PadRead and reads the same kind of raw buffer at 0x8001F4C0. The code lives in an unreachable 0x50C-byte function at 0x800122A4.

## Controllers

Each port's type is decided per read from the raw buffer, so any mix works in either port and an ordinary pad behaves exactly as before.

| Controller | Raw data used | Detection | Buttons (in play / menus) |
| --- | --- | --- | --- |
| PS Mouse | ID 0x12; byte 3 bits 3/2 = left/right (active low); bytes 4/5 = signed dX/dY, consumed after reading | ID | Left = catch, right = throw / left = X, right = TRIANGLE; both = START |
| NeGcon | ID 0x23; byte 4 twist (0x80 centre); bytes 5/6/7 analog I/II/L | ID 0x23 plus any NeGcon-only input on 3 reads in a row (2 in the selector) | As wired; I/II/L past 0x60 count as X/SQUARE/L1 |
| Namco Volume (SLPH-00015) | Same ID 0x23; byte 4 knob 0x00-0xFF; A on the START bit, B on the CIRCLE bit; I/II/L always 0 | Default for ID 0x23 until NeGcon-only input shows up | A = catch, B = throw, A then B = pull down, both 2 s = pause / knob = up/down, B + knob = left/right, A = X, B tap = TRIANGLE, A+B = START |
| JP3 spinner on a digital pad | LEFT = phase A, RIGHT = phase B | First read with LEFT and RIGHT both pressed (a d-pad can't) | Other buttons unchanged; LEFT/RIGHT never reach the game |

- **Volume vs NeGcon**: they share the ID and the report format. A Volume can never send I, II, L, the d-pad, B, R or SELECT, so the port is a Volume until one of those shows on consecutive reads. The switch is permanent until unplug. A read with I, II and L all at 0xF0+ is treated as a failed read, not as a NeGcon.
- **JP3 decode**: position = A xor 3B maps 00/10/11/01 to 0/1/2/3; delta mod 4 gives +1, -1, or 2 (both phases changed). The PS1 reads once per frame, so a 2 is counted as two edges in the last direction rather than dropped, keeping up to 2 edges per frame.
- **Unplug**: 30 failed reads, or a different ID, resets the JP3 latch and the Volume/NeGcon decision.

## In-game paddle model and visuals

The clown follows a virtual paddle position of 128 units per column, one column per tick, through the game's own left/right code so sounds, animation and column limits are untouched.

- **Hook**: 0x8003575C, the clown movement routine (s0 = player struct, s2 = this tick's buttons). Computer players are skipped.
- **Player struct**: +0x18 column, +0x1C colour held, +0x20 balloons held, +0x358 catch mask, +0x35A throw mask, +0x35C pull-down mask, +0x362 / +0x364 left / right masks, +0x366 buttons. The masks follow Set operation, so injected presses use them.
- **Relative inputs** (mouse, JP3): units per count from MOUSE SPEED (1, 2, 4, 8). Hysteresis of 8 units past a column edge. After 8 idle ticks the position re-centres in its column. JP3 = 8 counts per edge, so 4 edges per column at x1.
- **Absolute inputs**: NeGcon twist maps centre +-0x60 across the field (the spring returns it to the middle). Volume maps the knob's vlo..vhi (0x00..0xFF) across the field.
- **Magnet**: over a column whose bottom balloon matches the held colour, the mouse moves at half speed; for absolute inputs the column gets 4x hysteresis instead.
- **Glide**: clown X (0x80025130) and the aim line X (0x80024D84) are drawn at the paddle position, clamped to within one column of the real column.
- **Pulsing column**: the balloon loop (0x80024564) sets the fade brightness (0x800A918E) per cell; the target column gets a 12-step triangle wave (64 to 160, 4 frames each); 0x80024990 restores the game's value after the loop.
- **Unlock**: the card select's three reads of the unlock flags (0x8005E748 / 7C8 / 800, flags at 0x800D84EC) read as all set. Save data is untouched.

## Menus, card select, name entry, Options row

Outside play, movement is turned into single d-pad taps written into the game's own held and pressed words (0x800A911C / 0x800A9144), so every menu reacts as if the pad was used.

- **Steps**: 20 mouse counts per step, at most one per tick, remainder carried. The menus react to exactly one direction, so when both axes reach a step the larger wins. Volume knob counts as Y (up/down), or X while B is held; 2 counts per knob step.
- **Card select** (cursor routine 0x8005E5BC): mouse X and NeGcon twist walk the 23 cards in reading order through a table (hidden block, upper row, lower row), wrapping. The Volume uses an absolute dial instead: 23 zones over the knob range, 2 knob steps of hysteresis per edge, nothing moves until the knob enters a new zone. Solo and Competition use the game's own LEFT/RIGHT. The new cursor goes back through the game's routine, so sound and portrait update normally.
- **Name entry** (hook 0x8003BE74): its own accumulator, 8 mouse counts per letter, letters wrap.
- **Options row**: a 9th row, MOUSE SPEED x0.25 / x0.5 / x1 / x2, drawn with the game's text routine. Hooks: item table 0x8005FE18 (pointed at a 9-row copy), row count 0x8005FE4C, cursor routine 0x8005D084, value draw 0x8005FF54, Score display y 0x8009A79A moved down one line. Labels per EXE language ("Vel. raton" fits the Spanish width).
- **Tuning block**: a 44-byte block starting with "PDCF" holds every constant (step sizes, hysteresis, settle, speeds, magnet, pulse table, NeGcon ranges, JP3 counts, Volume range). It moves per build; the changes file lists its offsets.

## NTSC and English builds

Four builds come from the same game code: PAL and NTSC, each with or without the language screen.

- **NTSC 60 Hz**: the game logic runs once per frame and its timers are frame counts, so PAL ran about 17% slow; switching the video mode restores full speed. Only `SetVideoMode` and the screen position/offset constants change, in each game EXE and in the selector (0x80011474, 0x80011540, 0x8001155C, 0x8001156C, 0x80011574). The Volume pause hold scales with it: 100 frames PAL, 120 NTSC.
- **English start**: in the selector, the call at 0x80011660 that runs the flag screen becomes `ori v0, zero, 0`, so the caller loads MD3EN.EXE straight away. Built with armips `-equ SKIPLANG 1`; the game EXEs are identical across builds.
- **Build flags**: build.py `--ntsc`, `--nounlock`; armips `-equ NTSC n -equ SKIPLANG n` for the selector. armips refuses `equ` inside an `.if` block, so derived constants are written as expressions (`100 + NTSC*20`).

## R3000 pitfalls hit on this project

The emulator hid two real-hardware bugs; both are now checked automatically by tools/hazards.py.

| Pitfall | What happened | Rule |
| --- | --- | --- |
| Load delay | `lbu t8` in a branch delay slot, then `bnez t8`: the branch saw the old t8 and the chord state never stuck. The selector's NeGcon twist had the same bug since the first release. | Never use a loaded register in the very next executed instruction, including the branch target when the load sits in a delay slot. |
| MFLO / MULT | `mflo` followed at once by `div` | Two instructions between `mflo`/`mfhi` and the next `mult`/`div`. |
| Pseudo-ops in delay slots | `la` / `lw reg, label` expand to two instructions | Keep them out of delay slots. |
| Cross-chunk branches | Chunks land anywhere, so a branch can be out of range | Local trampoline with `j`. |
| armips labels | A static `@label` also ends the `@@` scope | Pass status back in a register instead of jumping into the caller's locals. |
| Failed reads | A flaky link reset detection and swapped Volume/NeGcon handling | Hold the last word; reset only after 30 failures; ignore stale buffers. |

Emulator quirks worth knowing: PCSX-ReARMed's libretro NeGcon device is 0x305, not 0x205. Switching a port's device in a test triggers the game's controller-removed pause, which looks like a pause from your code.

## Toolchain and test harness

Everything builds from source with Python 3 and armips, and a clean build reproduces the released images byte for byte.

| Tool | Job |
| --- | --- |
| `tools/extract_exes.py`, `iso.py` | Pull the EXEs out of the BIN (ISO 9660 walk) |
| `tools/build.py` | Signatures, free-space search, chunk packing, armips run, build\_log.json with every placement |
| `src/md3psx_paddle.asm`, `src/sles_paddle.asm` | The game patch and the selector patch |
| `tools/patchdisc.py`, `cdsec.py` | Write files back in place; rewrite only changed sectors with fresh Mode 2 Form 1 EDC/ECC |
| `tools/make_ppf.py`, xdelta3 | PPF 3.0 and xdelta patches against the Redump BIN |
| `tools/hazards.py` | Load-delay and MFLO hazard check over the asm sources |
| `test/retro.py` | ctypes libretro frontend for PCSX-ReARMed: scripted pad / mouse / NeGcon input, savestates, RAM reads |
| `third_party/pcsx_rearmed_debug_hooks.diff` | Breakpoint, watchpoint and coverage hooks in the interpreter (used for free-space proof and debugging) |
| `test/*.py` | seq, mkstates, langtest (six languages), jp3test, voltest, volmenu, volchord, glitchtest (flaky link) |

Testing habits that paid off: assert game state from RAM through the build's symbol file instead of trusting screenshots, rebuild savestates after every relocation (they contain the old code), and use watchpoints to find who writes a byte.

## Browser patcher

The single-file HTML patcher decodes a CHD v5 or reads a BIN in a Web Worker, verifies the Redump CRC32, applies the patch and writes a CHD or BIN+CUE, all offline.

- **CHD map**: Huffman-coded types (16 codes, max 8 bits, RLE-imported tree), then per hunk lengthbits / selfbits / parentbits fields; the map's CRC16 is checked.
- **CD codecs**: an ECC bitmap and a 2- or 3-byte base length come first. cdlz = raw LZMA (lc 3, lp 0, pb 2), cdzl = raw deflate, cdfl = FLAC (stereo 16-bit, written big-endian), each followed by zlib subcode. Sectors flagged in the bitmap get their sync and ECC regenerated (Mode 2 treats the first 4 header bytes as 0).
- **CHD output**: unchanged hunks are copied byte for byte from the source file (Blob slices, no re-encode). Changed hunks are stored uncompressed. The new map uses 16 fixed 4-bit codes, so no Huffman encoder is needed. Raw SHA-1 and overall SHA-1 (raw SHA-1 plus sorted tag + SHA-1 of each checksummed metadata entry) are recomputed; libchdr reads the result.
- **Delivery**: artifact downloads only allow a short list of extensions, so the output is a stored (uncompressed) ZIP; its CRC32 comes from a CRC32-combine of the copied parts. Opened from disk, the page falls back to a normal download link.
- **Speed**: about 40 to 55 s to patch a 200 MB CHD in Chromium; BIN to BIN takes about 4 s.
- **Verified**: every variant was patched end to end in headless Chromium and compared with the built images.

## Reuse checklist for the next project

1. Get the exact source image and its CRC32 first; every patch and the patcher check against it.
2. Find the game's input routine and held/pressed words; inject into those rather than patching each screen.
3. Replace the pad driver with InitPAD/StartPAD raw buffers early; it is what makes mouse, NeGcon and analog data visible at all.
4. Prove free space with static reachability plus play coverage before placing code; move the heap if the EXE tail is used.
5. Keep chunks small (below the ninth-largest hole) and let the packer place them; never hard-code addresses.
6. Find per-language or per-region sites by masked signatures and verify the original instructions before writing.
7. Keep every tunable in one tagged block so it can be adjusted without rebuilding.
8. Run hazards.py on every build; test on real hardware for timing and link problems the emulator hides.
9. Rebuild savestates after code moves; assert state from RAM via the symbol file.
10. Ship a browser patcher that takes CHD or BIN; the CHD reader/writer and stored-ZIP output are reusable as-is.
