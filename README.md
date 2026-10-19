# Magical Drop III (PS1) Paddle Edition

Patches for **Magical Drop III (Europe) (En,Fr,De,Es,It,Nl)**, SLES-02964, that let the
clown be driven like the Neo Geo Paddle Edition:

- **PlayStation Mouse** and **NeGcon** drive a virtual paddle
- **Namco Volume** (SLPH-00015): knob = paddle, A = catch, B = throw, A then B = pull down, hold both 2 s = pause
- **JP3 spinner** on d-pad LEFT/RIGHT, auto-enabled when LEFT+RIGHT arrive together
- Ordinary pads work exactly as before, in either port
- Four builds: PAL, PAL English-start, NTSC 60 Hz, NTSC 60 Hz English-start

Full behaviour: [docs/CHANGES.txt](docs/CHANGES.txt). How it works: [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Using the patches

You need the Redump BIN: 455,700,000 bytes, CRC32 `FE561E70`.

- **Browser:** open `releases/MD3 Paddle Edition Patcher.html`, pick your CHD or BIN, choose a build and output format (CHD or BIN+CUE). Runs offline.
- **xdelta / PPF:** `releases/Magical Drop III Paddle Edition patches.zip` has both for every build.

Expected output CRC32s: PAL `6A644BE1`, PAL English `804A7D47`, NTSC `4C9B268E`, NTSC English `A6B51028`.

## Building from source

Requires Python 3, [armips](https://github.com/Kingcom/armips), xdelta3 and zip.

```sh
ARMIPS=/path/to/armips XDELTA3=/path/to/xdelta3 scripts/build_all.sh "Magical Drop III (Europe).bin"
```

Outputs land in `build/` (patched BINs) and `releases/` (patches, patcher, zip). A clean build reproduces the release CRCs above.

## Layout

| Path | Contents |
|---|---|
| `src/` | `md3psx_paddle.asm` (game EXEs), `sles_paddle.asm` (language selector) |
| `tools/` | EXE extraction, signature search and chunk packer (`build.py`), disc patcher, PPF writer, hazard checker |
| `web/` | Browser patcher: CHD v5 reader/writer, patch core, template, builder, Node/Playwright tests |
| `test/` | libretro harness for PCSX-ReARMed (`retro.py`) and scripted tests; set `PCSX_CORE` to the core `.so` |
| `docs/` | Change list and technical breakdown (the patcher also has a plain-language "How it works" tab) |
| `releases/` | Release patches and patcher |

No game data is included; everything is applied to your own disc image.
