#!/usr/bin/env bash
# Build all four Paddle Edition variants, their patches and the browser patcher
# from the original Redump BIN.
#
#   scripts/build_all.sh path/to/original.bin
#
# Needs: python3 (numpy), armips, xdelta3. Set ARMIPS / XDELTA3 if they are not
# on PATH. Output: build/ (work files and patched BINs), dist/ (release files).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(realpath "${1:?usage: build_all.sh original.bin}")"
ARMIPS="${ARMIPS:-armips}"; XDELTA3="${XDELTA3:-xdelta3}"; export ARMIPS
B="$ROOT/build"; D="$ROOT/dist"
cd "$ROOT"

crc() { python3 -c "import zlib,sys
c=0
with open(sys.argv[1],'rb') as f:
    for b in iter(lambda: f.read(1<<24), b''): c=zlib.crc32(b,c)
print('%08X'%c)" "$1"; }

echo "== checking the source image"
[ "$(crc "$BIN")" = "FE561E70" ] || { echo "not the Redump Magical Drop III (Europe) BIN (CRC32 FE561E70)"; exit 1; }

rm -rf "$B"; mkdir -p "$B/orig" "$B/patchdata" "$D/patches"
python3 tools/extract_exes.py "$BIN" "$B/orig" >/dev/null

echo "== game EXEs"
python3 tools/build.py "$B/orig" "$B/pal"
python3 tools/build.py "$B/orig" "$B/ntsc" --ntsc
python3 tools/hazards.py src/md3psx_paddle.asm src/sles_paddle.asm | tee "$B/hazards.txt"
[ ! -s "$B/hazards.txt" ] || { echo "load-delay hazards found"; exit 1; }

echo "== language selector"
for v in pal:0 ntsc:1; do
  d="$B/${v%%:*}"; n="${v##*:}"
  "$ARMIPS" src/sles_paddle.asm -strequ INFILE "$B/orig/SLES_029.64" -strequ OUTFILE "$d/SLES_029.64"    -equ NTSC "$n" -equ SKIPLANG 0
  "$ARMIPS" src/sles_paddle.asm -strequ INFILE "$B/orig/SLES_029.64" -strequ OUTFILE "$d/SLES_029.64.en" -equ NTSC "$n" -equ SKIPLANG 1
done

echo "== disc images and patches"
declare -A NAME=([p]="PAL" [pe]="PAL, English" [n]="NTSC 60Hz" [ne]="NTSC 60Hz, English")
declare -A KEY=([p]=pal [pe]=pale [n]=ntsc [ne]=ntsce)
for v in p pe n ne; do
  d="$B/pal"; [[ $v == n* ]] && d="$B/ntsc"
  sles="$d/SLES_029.64"; [[ $v == *e ]] && sles="$d/SLES_029.64.en"
  args=(); for L in EN FR GE IT SP NL; do args+=("MD3$L.EXE=$d/MD3$L.EXE"); done
  python3 tools/patchdisc.py "$BIN" "$B/md3$v.bin" "${args[@]}" "SLES_029.64=$sles" >/dev/null
  printf 'FILE "md3%s.bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n' "$v" > "$B/md3$v.cue"
  out="$D/patches/Magical Drop III Paddle Edition (${NAME[$v]})"
  "$XDELTA3" -e -9 -f -s "$BIN" "$B/md3$v.bin" "$out.xdelta"
  python3 tools/make_ppf.py "$BIN" "$B/md3$v.bin" "$out.ppf" "Magical Drop III PS1 Paddle Edition ${NAME[$v]}" >/dev/null
  python3 web/make_patchdata.py "$BIN" "$B/md3$v.bin" "$B/patchdata/patch_${KEY[$v]}.b64" >/dev/null
  echo "  ${NAME[$v]}: CRC32 $(crc "$B/md3$v.bin")"
done

echo "== browser patcher"
python3 web/build_html.py "$B/patchdata" "$D/MD3 Paddle Edition Patcher.html"
cp docs/CHANGES.txt "$D/patches/MD3_PS1_Paddle_Edition_changes.txt"
(cd "$D/patches" && rm -f ../"Magical Drop III Paddle Edition patches.zip" && zip -q -X ../"Magical Drop III Paddle Edition patches.zip" ./*)
echo "done: dist/"
