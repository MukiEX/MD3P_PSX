// ---------------------------------------------------------------------------
//  Patch job: verifies the source image, applies the patch and builds the
//  output (CHD with only the touched hunks rewritten, or BIN + CUE).
//  src = { size, read(off,len)->Uint8Array, slice(off,len)->blob part }
// ---------------------------------------------------------------------------
'use strict';
const MD3 = {
  binSize: 455700000, frames: 193750,
  crcOrig: 0xFE561E70, crcPatched: { pal: 0xACB56D5B, pale: 0x469B5BFD, ntsc: 0xE56CEFBC, ntsce: 0x0F42D91A }, crcOld: { pal: [0x4FC1C72E, 0x1C247A04, 0x2CDDC68C, 0x1E704F8E, 0x2093B8BC, 0x070D00B1, 0xED233617, 0x6A644BE1, 0x804A7D47], ntsc: [0x6013F100, 0x33F64C2A, 0x030FF0A2, 0x31A279A0, 0x0F418E92, 0x28DF369F, 0xC2F10039, 0x4C9B268E, 0xA6B51028] },
};

function parsePatch(z) {
  // z: raw-deflated record list. Returns Map(sector -> [[offInSector, bytes], ...])
  const buf = new Uint8Array(1 << 20); const n = INF(z, 0, z.length, buf, 0, buf.length);
  const dv = new DataView(buf.buffer, 0, n); const cnt = dv.getUint32(0, true); let p = 4;
  const bySector = new Map();
  for (let i = 0; i < cnt; i++) {
    let off = dv.getUint32(p, true), len = dv.getUint16(p + 4, true); p += 6;
    let data = buf.slice(p, p + len); p += len;
    while (len > 0) {
      const sec = Math.floor(off / SECT), so = off % SECT, k = Math.min(len, SECT - so);
      if (!bySector.has(sec)) bySector.set(sec, []);
      bySector.get(sec).push([so, data.subarray(0, k)]);
      off += k; len -= k; data = data.subarray(k);
    }
  }
  return bySector;
}

function applySector(list, dst, base) { for (const [so, d] of list) dst.set(d, base + so); }

function hex8(x) { return (x >>> 0).toString(16).toUpperCase().padStart(8, '0'); }

function checkCrc(crc, variant) {
  if (crc === MD3.crcOrig) return;
  for (const k in MD3.crcOld) if (MD3.crcOld[k].includes(crc)) throw new Error('This image has an earlier ' + (k === 'pal' ? 'PAL' : 'NTSC 60 Hz') + ' Paddle Edition patch. Please start from the original disc image.');
  for (const k in MD3.crcPatched) if (crc === MD3.crcPatched[k]) throw new Error('This image has already been patched (' + (k.startsWith('pal') ? 'PAL' : 'NTSC 60 Hz') + (k.endsWith('e') ? ', English' : '') + ' Paddle Edition). Please start from the original disc image.');
  throw new Error('This is not the expected Magical Drop III (Europe) disc image: data CRC32 is ' + hex8(crc) + ', expected ' + hex8(MD3.crcOrig) + ' (Redump). The patch was not applied.');
}

// --------------------------------------------------------------- CHD input
function patchCHD(src, patchZ, variant, outFmt, progress) {
  const chd = new CHD(src.read, src.size);
  if (chd.tracks.length !== 1) throw new Error('Expected a single-track disc in the CHD, found ' + chd.tracks.length + ' tracks.');
  const nfr = +chd.tracks[0].FRAMES;
  if (!/MODE2_RAW/.test(chd.tracks[0].TYPE) || nfr !== MD3.frames) throw new Error('Unexpected disc layout in CHD (' + chd.tracks[0].TYPE + ', ' + nfr + ' frames). Expected MODE2_RAW, ' + MD3.frames + ' frames.');
  const patch = parsePatch(patchZ);
  const hb = chd.hunkbytes, fph = chd.fph, H = chd.hunks;
  const touched = new Set(); for (const s of patch.keys()) touched.add(Math.floor(s / fph));
  const selfTargets = new Set(); for (let i = 0; i < H; i++) if (chd.mtype[i] === 5) selfTargets.add(chd.moff[i]);
  const cache = new Map();
  const dst = new Uint8Array(hb);
  let crcO = 0, crcP = 0, dcrc = 0;
  const sha = outFmt === 'chd' ? new SHA1() : null;
  const entries = [], dataParts = [], binParts = [];
  let binChunk = null, binPos = 0; const BINCH = 64 * 8 * SECT;
  // batched reads of the compressed stream (it's stored in hunk order)
  let rbuf = null, rbOff = 0, rbEnd = 0;
  const getComp = (off, len) => {
    if (off < rbOff || off + len > rbEnd) { const want = Math.max(len, 4 << 20); const l = Math.min(want, src.size - off); rbuf = src.read(off, l); rbOff = off; rbEnd = off + l; }
    return rbuf.subarray(off - rbOff, off - rbOff + len);
  };
  let lastTick = 0;
  for (let i = 0; i < H; i++) {
    const t = chd.mtype[i];
    if (t === 5) { const c = cache.get(chd.moff[i]); if (!c) throw new Error('bad self reference'); dst.set(c); }
    else chd.decodeHunk(i, getComp(chd.moff[i], t === 4 ? hb : chd.mlen[i]), dst);
    if (selfTargets.has(i)) cache.set(i, dst.slice());
    const f0 = i * fph, nf = Math.max(0, Math.min(fph, nfr - f0));
    for (let f = 0; f < nf; f++) crcO = crc32(crcO, dst, f * FRAME, f * FRAME + SECT);
    const isT = touched.has(i);
    if (isT) for (let f = 0; f < nf; f++) { const l = patch.get(f0 + f); if (l) applySector(l, dst, f * FRAME); }
    for (let f = 0; f < nf; f++) crcP = crc32(crcP, dst, f * FRAME, f * FRAME + SECT);
    if (outFmt === 'chd') {
      const lim = Math.min(hb, chd.logical - i * hb); sha.update(dst, 0, lim);
      if (isT || (t === 5 && touched.has(chd.moff[i]))) { entries.push({ type: 4, crc: crc16(dst) }); dataParts.push(dst.slice()); dcrc = crc32(dcrc, dst); }
      else if (t === 5) entries.push({ type: 5, self: chd.moff[i] });
      else { const L = t === 4 ? hb : chd.mlen[i]; entries.push({ type: t, len: L, crc: chd.mcrc[i] }); dataParts.push(src.slice(chd.moff[i], L)); dcrc = crc32(dcrc, getComp(chd.moff[i], L)); }
    } else {
      for (let f = 0; f < nf; f++) {
        if (!binChunk) { binChunk = new Uint8Array(BINCH); binPos = 0; }
        binChunk.set(dst.subarray(f * FRAME, f * FRAME + SECT), binPos); binPos += SECT;
        if (binPos === BINCH) { binParts.push(binChunk); binChunk = null; }
      }
    }
    if (progress && (i - lastTick >= 64 || i === H - 1)) { lastTick = i; progress((i + 1) / H); }
  }
  if (binChunk) binParts.push(binChunk.subarray(0, binPos));
  checkCrc(crcO >>> 0, variant);
  if (crcP >>> 0 !== MD3.crcPatched[variant]) throw new Error('Internal error: patched data CRC32 ' + hex8(crcP) + ' does not match the expected ' + hex8(MD3.crcPatched[variant]) + '.');
  if (outFmt !== 'chd') return { parts: binParts, crc: crcP >>> 0, fileCrc: crcP >>> 0, fileSize: nfr * SECT };

  // ---- assemble the new CHD
  const rawsha = sha.digest();
  const metaBlocks = []; let off = 124; const metaOff = chd.meta.length ? 124 : 0;
  chd.meta.forEach((m, k) => {
    const b = new Uint8Array(16 + m.data.length), next = k + 1 < chd.meta.length ? off + b.length : 0;
    b.set(m.tag, 0); b[4] = m.flags; b[5] = m.data.length >>> 16; b[6] = m.data.length >>> 8; b[7] = m.data.length;
    const dv = new DataView(b.buffer); dv.setUint32(8, Math.floor(next / 4294967296)); dv.setUint32(12, next >>> 0);
    b.set(m.data, 16); metaBlocks.push(b); off += b.length;
  });
  const firstoffs = off;
  let dataLen = 0; for (const e of entries) if (e.type <= 4) dataLen += e.type === 4 ? hb : e.len;
  const mapOff = firstoffs + dataLen;
  const [mh, mb] = buildMap(entries, firstoffs, hb);
  const hashes = chd.meta.filter(m => m.flags & 1).map(m => { const b = new Uint8Array(24); b.set(m.tag); b.set(new SHA1().update(m.data).digest(), 4); return b; });
  hashes.sort((a, b) => { for (let i = 0; i < 24; i++) if (a[i] !== b[i]) return a[i] - b[i]; return 0; });
  const ov = new SHA1().update(rawsha); hashes.forEach(h => ov.update(h));
  const hdr = chd.hdr.slice(); const hv = new DataView(hdr.buffer);
  const put64 = (o, v) => { hv.setUint32(o, Math.floor(v / 4294967296)); hv.setUint32(o + 4, v >>> 0); };
  put64(40, mapOff); put64(48, metaOff); hdr.set(rawsha, 64); hdr.set(ov.digest(), 84);
  let fc = crc32(0, hdr); for (const b of metaBlocks) fc = crc32(fc, b);
  fc = crc32Combine(fc, dcrc >>> 0, dataLen); fc = crc32(fc, mh); fc = crc32(fc, mb);
  return { parts: [hdr, ...metaBlocks, ...dataParts, mh, mb], crc: crcP >>> 0, fileCrc: fc >>> 0, fileSize: firstoffs + dataLen + 16 + mb.length, rawsha };
}

// --------------------------------------------------------------- BIN input
function patchBIN(src, patchZ, variant, progress) {
  if (src.size !== MD3.binSize) throw new Error('Unexpected BIN size: ' + src.size.toLocaleString('en') + ' bytes (expected ' + MD3.binSize.toLocaleString('en') + '). Use the single-track Redump BIN.');
  const patch = parsePatch(patchZ);
  const secs = [...patch.keys()].sort((a, b) => a - b);
  let crcO = 0, crcP = 0; const CH = 8 << 20;
  const parts = []; let si = 0, cursor = 0;
  for (let off = 0; off < src.size; off += CH) {
    const len = Math.min(CH, src.size - off); const a = src.read(off, len);
    crcO = crc32(crcO, a);
    // patch sectors that fall in this chunk (chunk size is a multiple of nothing in particular: handle partial sectors)
    let pa = null;
    while (si < secs.length && secs[si] * SECT < off + len) {
      const s = secs[si]; const so = s * SECT;
      for (const [o, d] of patch.get(s)) {
        const abs = so + o; // records are split per sector; may still straddle the chunk edge
        for (let k = 0; k < d.length; k++) { const q = abs + k - off; if (q >= 0 && q < len) { if (!pa) pa = a.slice(); pa[q] = d[k]; } }
      }
      if (so + SECT <= off + len) si++; else break;
    }
    const outA = pa || a;
    crcP = crc32(crcP, outA);
    parts.push(pa ? pa : src.slice(off, len));
    if (progress) progress((off + len) / src.size);
  }
  checkCrc(crcO >>> 0, variant);
  if (crcP >>> 0 !== MD3.crcPatched[variant]) throw new Error('Internal error: patched CRC32 mismatch.');
  return { parts, crc: crcP >>> 0, fileCrc: crcP >>> 0, fileSize: src.size };
}

if (typeof module !== 'undefined') module.exports = { MD3, patchCHD, patchBIN, parsePatch };
