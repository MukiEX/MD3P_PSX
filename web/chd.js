// ---------------------------------------------------------------------------
//  Minimal CHD v5 (CD) reader/writer + codecs for the browser (also runs in
//  Node for testing). LZMA, inflate and FLAC decoders are self-contained.
// ---------------------------------------------------------------------------
'use strict';

// ------------------------------------------------------------------ CRCs
const CRC32_T = (() => { const t = new Int32Array(256); for (let i = 0; i < 256; i++) { let c = i; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[i] = c; } return t; })();
function crc32(c, a, s = 0, e = a.length) { c = ~c; for (let i = s; i < e; i++) c = CRC32_T[(c ^ a[i]) & 255] ^ (c >>> 8); return ~c >>> 0; }
const CRC16_T = (() => { const t = new Uint16Array(256); for (let i = 0; i < 256; i++) { let c = i << 8; for (let k = 0; k < 8; k++) c = c & 0x8000 ? (c << 1) ^ 0x1021 : c << 1; t[i] = c & 0xffff; } return t; })();
function crc32Combine(c1, c2, len2) {
  if (len2 <= 0) return c1;
  const times = (m, v) => { let s = 0, i = 0; while (v) { if (v & 1) s ^= m[i]; v >>>= 1; i++; } return s >>> 0; };
  const sq = (d, m) => { for (let n = 0; n < 32; n++) d[n] = times(m, m[n]); };
  const even = new Uint32Array(32), odd = new Uint32Array(32); odd[0] = 0xEDB88320; let row = 1; for (let n = 1; n < 32; n++) { odd[n] = row; row <<= 1; }
  sq(even, odd); sq(odd, even);
  do { sq(even, odd); if (len2 % 2) c1 = times(even, c1); len2 = Math.floor(len2 / 2); if (!len2) break; sq(odd, even); if (len2 % 2) c1 = times(odd, c1); len2 = Math.floor(len2 / 2); } while (len2);
  return (c1 ^ c2) >>> 0;
}
function crc16(a, s = 0, e = a.length) { let c = 0xffff; for (let i = s; i < e; i++) c = ((c << 8) ^ CRC16_T[((c >>> 8) ^ a[i]) & 255]) & 0xffff; return c; }

// ------------------------------------------------------------------ SHA-1 (incremental)
class SHA1 {
  constructor() { this.h = new Int32Array([0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]); this.buf = new Uint8Array(64); this.bl = 0; this.len = 0; this.w = new Int32Array(80); }
  _block(a, o) {
    const w = this.w, h = this.h; for (let i = 0; i < 16; i++, o += 4) w[i] = (a[o] << 24) | (a[o + 1] << 16) | (a[o + 2] << 8) | a[o + 3];
    for (let i = 16; i < 80; i++) { const x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]; w[i] = (x << 1) | (x >>> 31); }
    let A = h[0], B = h[1], C = h[2], D = h[3], E = h[4], t = 0, i = 0;
    for (; i < 20; i++) { t = (((A << 5) | (A >>> 27)) + ((B & C) | (~B & D)) + E + 0x5A827999 + w[i]) | 0; E = D; D = C; C = (B << 30) | (B >>> 2); B = A; A = t; }
    for (; i < 40; i++) { t = (((A << 5) | (A >>> 27)) + (B ^ C ^ D) + E + 0x6ED9EBA1 + w[i]) | 0; E = D; D = C; C = (B << 30) | (B >>> 2); B = A; A = t; }
    for (; i < 60; i++) { t = (((A << 5) | (A >>> 27)) + ((B & C) | (B & D) | (C & D)) + E - 0x70E44324 + w[i]) | 0; E = D; D = C; C = (B << 30) | (B >>> 2); B = A; A = t; }
    for (; i < 80; i++) { t = (((A << 5) | (A >>> 27)) + (B ^ C ^ D) + E - 0x359D3E2A + w[i]) | 0; E = D; D = C; C = (B << 30) | (B >>> 2); B = A; A = t; }
    h[0] += A; h[1] += B; h[2] += C; h[3] += D; h[4] += E;
  }
  update(a, s = 0, e = a.length) {
    this.len += e - s;
    if (this.bl) { while (s < e && this.bl < 64) this.buf[this.bl++] = a[s++]; if (this.bl === 64) { this._block(this.buf, 0); this.bl = 0; } }
    while (e - s >= 64) { this._block(a, s); s += 64; }
    while (s < e) this.buf[this.bl++] = a[s++];
    return this;
  }
  digest() {
    const bits = this.len * 8, pad = new Uint8Array(((this.bl < 56) ? 56 : 120) - this.bl + 8); pad[0] = 0x80;
    const hi = Math.floor(bits / 4294967296), lo = bits >>> 0, n = pad.length;
    pad[n - 8] = hi >>> 24; pad[n - 7] = hi >>> 16; pad[n - 6] = hi >>> 8; pad[n - 5] = hi; pad[n - 4] = lo >>> 24; pad[n - 3] = lo >>> 16; pad[n - 2] = lo >>> 8; pad[n - 1] = lo;
    this.update(pad); const out = new Uint8Array(20);
    for (let i = 0; i < 5; i++) { out[i * 4] = this.h[i] >>> 24; out[i * 4 + 1] = this.h[i] >>> 16; out[i * 4 + 2] = this.h[i] >>> 8; out[i * 4 + 3] = this.h[i]; }
    return out;
  }
}

// ------------------------------------------------------------------ MSB-first bit reader
class BitReader {
  constructor(a, s = 0, e = a.length) { this.a = a; this.p = s; this.e = e; this.acc = 0; this.n = 0; }
  read(k) { if (k === 0) return 0; const v = this.peekBig(k); this.n -= k; this.acc = this.acc % Math.pow(2, this.n); return v; }
  peekBig(k) { while (this.n < k) { this.acc = this.acc * 256 + (this.p < this.e ? this.a[this.p] : 0); this.p++; this.n += 8; } return Math.floor(this.acc / Math.pow(2, this.n - k)); }
  overflow() { return this.p - Math.floor(this.n / 8) > this.e; }
}

// ------------------------------------------------------------------ CHD huffman (map)
function huffBuild(lens, maxbits) {
  const histo = new Uint32Array(33); for (const l of lens) histo[l]++;
  let cur = 0; for (let L = 32; L > 0; L--) { const nx = (cur + histo[L]) >> 1; if (L !== 1 && nx * 2 !== cur + histo[L]) throw new Error('bad huffman'); histo[L] = cur; cur = nx; }
  const lut = new Uint32Array(1 << maxbits).fill(1);
  lens.forEach((l, code) => { if (!l) return; const bits = histo[l]++; const sh = maxbits - l; for (let i = bits << sh; i < (bits + 1) << sh; i++) lut[i] = (code << 5) | l; });
  return lut;
}
function huffDecode(lut, maxbits, br) { const v = lut[br.peekBig(maxbits)]; br.read(v & 31); return v >>> 5; }

// ------------------------------------------------------------------ inflate (raw deflate)
const INF = (() => {
  const lbase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  const lext = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  const dbase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
  const dext = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
  const clord = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
  // table: counts per length + symbols sorted (puff style)
  function mk(lens, n) { const cnt = new Uint16Array(16), sym = new Uint16Array(n), off = new Uint16Array(16); for (let i = 0; i < n; i++) cnt[lens[i]]++; cnt[0] = 0; for (let i = 1; i < 16; i++) off[i] = off[i - 1] + cnt[i - 1]; for (let i = 0; i < n; i++) if (lens[i]) sym[off[lens[i]]++] = i; return { cnt, sym }; }
  const fl = new Uint8Array(288); fl.fill(8, 0, 144); fl.fill(9, 144, 256); fl.fill(7, 256, 280); fl.fill(8, 280, 288);
  const fixL = mk(fl, 288), fixD = mk(new Uint8Array(30).fill(5), 30);
  return function inflate(src, s, e, out, o, oe) {
    let p = s, bb = 0, bn = 0;
    const bits = (n) => { while (bn < n) { if (p >= e) throw new Error('inflate: input overrun'); bb |= src[p++] << bn; bn += 8; } const v = bb & ((1 << n) - 1); bb >>>= n; bn -= n; return v; };
    const dec = (h) => { let code = 0, first = 0, idx = 0; for (let len = 1; len < 16; len++) { code |= bits(1); const c = h.cnt[len]; if (code - c < first) return h.sym[idx + (code - first)]; idx += c; first += c; first <<= 1; code <<= 1; } throw new Error('inflate: bad code'); };
    let last;
    do {
      last = bits(1); const type = bits(2);
      if (type === 0) {
        bb = 0; bn = 0; const len = src[p] | (src[p + 1] << 8); p += 4;
        if (o + len > oe) throw new Error('inflate: output overrun'); out.set(src.subarray(p, p + len), o); p += len; o += len;
      } else {
        let L, D;
        if (type === 1) { L = fixL; D = fixD; } else if (type === 2) {
          const nl = bits(5) + 257, nd = bits(5) + 1, nc = bits(4) + 4, cl = new Uint8Array(19);
          for (let i = 0; i < nc; i++) cl[clord[i]] = bits(3);
          const ch = mk(cl, 19), ls = new Uint8Array(nl + nd);
          for (let i = 0; i < nl + nd;) { const sy = dec(ch); if (sy < 16) ls[i++] = sy; else { let rep, v = 0; if (sy === 16) { v = ls[i - 1]; rep = 3 + bits(2); } else if (sy === 17) rep = 3 + bits(3); else rep = 11 + bits(7); while (rep--) ls[i++] = v; } }
          L = mk(ls.subarray(0, nl), nl); D = mk(ls.subarray(nl), nd);
        } else throw new Error('inflate: bad block');
        for (;;) {
          let sy = dec(L);
          if (sy < 256) { if (o >= oe) throw new Error('inflate: output overrun'); out[o++] = sy; } else if (sy === 256) break; else {
            sy -= 257; const len = lbase[sy] + bits(lext[sy]); const ds = dec(D); const dist = dbase[ds] + bits(dext[ds]);
            if (o + len > oe) throw new Error('inflate: output overrun');
            for (let k = 0; k < len; k++, o++) out[o] = out[o - dist];
          }
        }
      }
    } while (!last);
    return o;
  };
})();

// ------------------------------------------------------------------ LZMA (raw stream, lc=3 lp=0 pb=2)
// { const ix = i; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } is expanded by the build script into an inlined range-decoder step that sets `b`.
const LZ_PROBS = new Uint16Array(1846 + 0x300 * 8);
function lzmaDecode(src, s, e, out, o0, outLen) {
  const probs = LZ_PROBS; probs.fill(1024);
  const IsRep = 192, IsRepG0 = 204, IsRepG1 = 216, IsRepG2 = 228, IsRep0Long = 240, PosSlot = 432, SpecPos = 688, Align = 802, LenC = 818, RepLenC = 1332, Literal = 1846;
  let p = s + 1, range = 4294967295, code = 0, b = 0, pr = 0, bound = 0, m = 0, i = 0, base = 0;
  for (let k = 0; k < 4; k++) code = code * 256 + src[p++];
  let state = 0, r0 = 0, r1 = 0, r2 = 0, r3 = 0, o = o0, len = 0; const oe = o0 + outLen;
  while (o < oe) {
    const pos = o - o0, ps = pos & 3;
    { const ix = (state << 4) + ps; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } }
    if (!b) {
      base = Literal + 0x300 * (pos > 0 ? out[o - 1] >> 5 : 0);
      let sym = 1;
      if (state >= 7) {
        let mb = out[o - r0 - 1];
        do { const mbit = (mb >> 7) & 1; mb <<= 1; { const ix = base + ((1 + mbit) << 8) + sym; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } sym = (sym << 1) | b; if (mbit !== b) break; } while (sym < 0x100);
      }
      while (sym < 0x100) { { const ix = base + sym; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } sym = (sym << 1) | b; }
      out[o++] = sym & 255;
      state = state < 4 ? 0 : state < 10 ? state - 3 : state - 6;
      continue;
    }
    { const ix = IsRep + state; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } }
    if (b) {
      if (pos === 0) throw new Error('lzma: bad rep');
      { const ix = IsRepG0 + state; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } }
      if (!b) {
        { const ix = IsRep0Long + (state << 4) + ps; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } }
        if (!b) { state = state < 7 ? 9 : 11; out[o] = out[o - r0 - 1]; o++; continue; }
      } else {
        let d; { const ix = IsRepG1 + state; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } }
        if (!b) d = r1; else { { const ix = IsRepG2 + state; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } if (!b) d = r2; else { d = r3; r3 = r2; } r2 = r1; }
        r1 = r0; r0 = d;
      }
      base = RepLenC; { const ix = base; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } if (!b) { base += 2 + (ps << 3); m = 1; for (i = 0; i < 3; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; } len = m - 8; } else { { const ix = base + 1; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } if (!b) { base += 130 + (ps << 3); m = 1; for (i = 0; i < 3; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; } len = 8 + m - 8; } else { base += 258; m = 1; for (i = 0; i < 8; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; } len = 16 + m - 256; } }
      state = state < 7 ? 8 : 11;
    } else {
      r3 = r2; r2 = r1; r1 = r0;
      base = LenC; { const ix = base; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } if (!b) { base += 2 + (ps << 3); m = 1; for (i = 0; i < 3; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; } len = m - 8; } else { { const ix = base + 1; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } if (!b) { base += 130 + (ps << 3); m = 1; for (i = 0; i < 3; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; } len = 8 + m - 8; } else { base += 258; m = 1; for (i = 0; i < 8; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; } len = 16 + m - 256; } }
      state = state < 7 ? 7 : 10;
      base = PosSlot + ((len < 4 ? len : 3) << 6); m = 1;
      for (i = 0; i < 6; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; }
      const slot = m - 64;
      if (slot < 4) r0 = slot; else {
        const nd = (slot >> 1) - 1; let d = (2 | (slot & 1)) * Math.pow(2, nd);
        if (slot < 14) { base = SpecPos + d - slot - 1; m = 1; for (i = 0; i < nd; i++) { { const ix = base + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; d += b << i; } }
        else {
          let r = 0;
          for (let k = nd - 4; k > 0; k--) { range = Math.floor(range / 2); if (code >= range) { code -= range; r = r * 2 + 1; } else r = r * 2; if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } }
          d += r * 16; m = 1;
          for (i = 0; i < 4; i++) { { const ix = Align + m; { pr = probs[ix]; bound = (range >>> 11) * pr; if (code < bound) { range = bound; probs[ix] = pr + ((2048 - pr) >> 5); b = 0; } else { range -= bound; code -= bound; probs[ix] = pr - (pr >> 5); b = 1; } if (range < 16777216) { range *= 256; code = code * 256 + (p < e ? src[p] : 0); p++; } } } m = (m << 1) | b; d += b << i; }
        }
        r0 = d;
      }
      if (r0 === 0xFFFFFFFF) break;
    }
    len += 2;
    if (r0 >= o - o0) throw new Error('lzma: bad distance');
    if (o + len > oe) len = oe - o;
    for (let k = 0; k < len; k++, o++) out[o] = out[o - r0 - 1];
  }
  return o;
}

// ------------------------------------------------------------------ FLAC (CD audio: 16-bit stereo)
function flacDecode(src, s, e, out, o, nsamp /* per channel */) {
  // returns byte offset (relative to src) just after the last frame consumed
  const br = { p: s, acc: 0, n: 0 };
  const rd = (k) => { if (k === 0) return 0; while (br.n < k) { br.acc = br.acc * 256 + (br.p < e ? src[br.p] : 0); br.p++; br.n += 8; } br.n -= k; const pw = Math.pow(2, br.n); const v = Math.floor(br.acc / pw); br.acc -= v * pw; return v; };
  const rds = (k) => { if (k === 0) return 0; const v = rd(k); return v >= Math.pow(2, k - 1) ? v - Math.pow(2, k) : v; };
  const align = () => { br.n -= br.n % 8; br.acc %= Math.pow(2, br.n); };
  const unary = () => { let q = 0; while (rd(1) === 0) q++; return q; };
  const ch = [new Int32Array(4608), new Int32Array(4608)];
  let done = 0;
  while (done < nsamp) {
    align();
    const sync = rd(14); if (sync !== 0x3FFE) throw new Error('flac: lost sync');
    rd(1); rd(1);
    const bsc = rd(4), src_ = rd(4), chas = rd(4), ssz = rd(3); rd(1);
    // utf-8 frame number
    let x = rd(8); if (x & 0x80) { let n = 0; while (x & (0x80 >> n)) n++; for (let i = 1; i < n; i++) rd(8); }
    let bs;
    if (bsc === 1) bs = 192; else if (bsc <= 5) bs = 576 << (bsc - 2); else if (bsc === 6) bs = rd(8) + 1; else if (bsc === 7) bs = rd(16) + 1; else bs = 256 << (bsc - 8);
    if (src_ === 12) rd(8); else if (src_ === 13 || src_ === 14) rd(16);
    rd(8); // crc8
    const bps = (ssz === 0) ? 16 : [0, 8, 12, 0, 16, 20, 24, 32][ssz];
    const nch = chas < 8 ? chas + 1 : 2;
    if (nch !== 2) throw new Error('flac: expected stereo');
    for (let c = 0; c < 2; c++) {
      let sbps = bps; if ((chas === 8 && c === 1) || (chas === 9 && c === 0) || (chas === 10 && c === 1)) sbps++;
      rd(1); const type = rd(6); let wasted = 0; if (rd(1)) wasted = unary() + 1; sbps -= wasted;
      const d = ch[c];
      if (type === 0) { const v = rds(sbps); for (let i = 0; i < bs; i++) d[i] = v; }
      else if (type === 1) { for (let i = 0; i < bs; i++) d[i] = rds(sbps); }
      else {
        let order, coefs = null, shift = 0;
        if (type >= 8 && type <= 12) order = type - 8; else if (type >= 32) order = type - 31; else throw new Error('flac: bad subframe');
        for (let i = 0; i < order; i++) d[i] = rds(sbps);
        if (type >= 32) { const prec = rd(4) + 1; shift = rds(5); coefs = []; for (let i = 0; i < order; i++) coefs.push(rds(prec)); }
        // residual
        const meth = rd(2), pbits = meth === 0 ? 4 : 5, esc = meth === 0 ? 15 : 31, po = rd(4), np = 1 << po;
        let i = order;
        for (let part = 0; part < np; part++) {
          const cnt = (bs >> po) - (part === 0 ? order : 0); const k = rd(pbits);
          if (k === esc) { const nb = rd(5); for (let j = 0; j < cnt; j++) d[i++] = rds(nb); }
          else for (let j = 0; j < cnt; j++) { const q = unary(); const u = q * Math.pow(2, k) + rd(k); d[i++] = (u % 2) ? -((u + 1) / 2) : u / 2; }
        }
        if (coefs) {
          const div = Math.pow(2, shift);
          for (let j = order; j < bs; j++) { let sum = 0; for (let t = 0; t < order; t++) sum += coefs[t] * d[j - t - 1]; d[j] += Math.floor(sum / div); }
        } else {
          for (let j = order; j < bs; j++) {
            switch (order) {
              case 1: d[j] += d[j - 1]; break;
              case 2: d[j] += 2 * d[j - 1] - d[j - 2]; break;
              case 3: d[j] += 3 * d[j - 1] - 3 * d[j - 2] + d[j - 3]; break;
              case 4: d[j] += 4 * d[j - 1] - 6 * d[j - 2] + 4 * d[j - 3] - d[j - 4]; break;
            }
          }
        }
      }
      if (wasted) for (let i = 0; i < bs; i++) d[i] *= (1 << wasted);
    }
    align(); rd(16); // crc16
    const L = ch[0], R = ch[1];
    for (let i = 0; i < bs && done < nsamp; i++, done++) {
      let l = L[i], r = R[i];
      if (chas === 8) r = l - r; else if (chas === 9) l = l + r; else if (chas === 10) { const m = l * 2 + (r & 1); l = (m + r) >> 1; r = (m - r) >> 1; }
      out[o++] = (l >> 8) & 255; out[o++] = l & 255; out[o++] = (r >> 8) & 255; out[o++] = r & 255;
    }
  }
  return br.p - Math.floor(br.n / 8);
}

// ------------------------------------------------------------------ CD sector ECC
const ECC_F = new Uint8Array(256), ECC_B = new Uint8Array(256);
for (let i = 0; i < 256; i++) { const j = ((i << 1) ^ (i & 0x80 ? 0x11d : 0)) & 255; ECC_F[i] = j; ECC_B[i ^ j] = i; }
function eccPart(sec, base, majc, minc, mult, inc, dst) {
  const size = majc * minc;
  for (let maj = 0; maj < majc; maj++) {
    let idx = (maj >> 1) * mult + (maj & 1), a = 0, b = 0;
    for (let mi = 0; mi < minc; mi++) { const t = sec[base + 12 + idx]; idx += inc; if (idx >= size) idx -= size; a ^= t; b ^= t; a = ECC_F[a]; }
    a = ECC_B[ECC_F[a] ^ b]; sec[base + dst + maj] = a; sec[base + dst + maj + majc] = a ^ b;
  }
}
const SYNC = [0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0];
function eccGenerate(sec, base) {
  for (let i = 0; i < 12; i++) sec[base + i] = SYNC[i];
  const m2 = sec[base + 15] === 2; let h;
  if (m2) { h = sec.slice(base + 12, base + 16); sec.fill(0, base + 12, base + 16); }
  eccPart(sec, base, 86, 24, 2, 86, 2076);
  eccPart(sec, base, 52, 43, 86, 88, 2248);
  if (m2) sec.set(h, base + 12);
}

// ------------------------------------------------------------------ CHD reader
const FRAME = 2448, SECT = 2352;
class CHD {
  // read(off, len) -> Uint8Array (sync)
  constructor(read, fileSize) {
    this.read = read; this.size = fileSize;
    const h = read(0, 124); this.hdr = h;
    const tag = String.fromCharCode(...h.subarray(0, 8));
    if (tag !== 'MComprHD') throw new Error('Not a CHD file');
    const dv = new DataView(h.buffer, h.byteOffset, h.byteLength);
    this.version = dv.getUint32(12);
    if (this.version !== 5) throw new Error('Only CHD version 5 is supported (this file is v' + this.version + '). Re-create it with a current chdman.');
    this.codecs = [0, 1, 2, 3].map(i => String.fromCharCode(...h.subarray(16 + i * 4, 20 + i * 4)).replace(/\0/g, ''));
    const u64 = (o) => dv.getUint32(o) * 4294967296 + dv.getUint32(o + 4);
    this.logical = u64(32); this.mapoff = u64(40); this.metaoff = u64(48);
    this.hunkbytes = dv.getUint32(56); this.unitbytes = dv.getUint32(60);
    this.hunks = Math.ceil(this.logical / this.hunkbytes);
    if (this.hdr.subarray(104, 124).some(x => x)) throw new Error('This CHD needs a parent CHD; please use a standalone CHD.');
    if (this.hunkbytes % FRAME) throw new Error('Not a CD-ROM CHD');
    this.fph = this.hunkbytes / FRAME;
    this.readMeta(); this.readMap();
  }
  readMeta() {
    this.meta = []; let o = this.metaoff;
    while (o) { const e = this.read(o, 16); const len = (e[5] << 16) | (e[6] << 8) | e[7]; const nx = new DataView(e.buffer, e.byteOffset).getUint32(8) * 4294967296 + new DataView(e.buffer, e.byteOffset).getUint32(12); this.meta.push({ tag: e.slice(0, 4), flags: e[4], data: this.read(o + 16, len) }); o = nx; }
    this.tracks = [];
    for (const m of this.meta) { const t = String.fromCharCode(...m.tag); if (t === 'CHT2' || t === 'CHTR') { const s = new TextDecoder().decode(m.data).replace(/\0.*$/, ''); const kv = {}; s.split(' ').forEach(w => { const i = w.indexOf(':'); if (i > 0) kv[w.slice(0, i)] = w.slice(i + 1); }); this.tracks.push(kv); } }
  }
  readMap() {
    const n = this.hunks, hb = this.hunkbytes;
    this.mtype = new Uint8Array(n); this.mlen = new Uint32Array(n); this.moff = new Float64Array(n); this.mcrc = new Uint16Array(n);
    if (this.codecs.every(c => !c)) throw new Error('Uncompressed CHDs are not supported; please convert to BIN/CUE first.');
    const mh = this.read(this.mapoff, 16), dv = new DataView(mh.buffer, mh.byteOffset);
    const mapbytes = dv.getUint32(0), firstoffs = dv.getUint16(4) * 4294967296 + dv.getUint32(6), mapcrc = dv.getUint16(10);
    const lb = mh[12], sb = mh[13], pb = mh[14];
    const data = this.read(this.mapoff + 16, mapbytes);
    const br = new BitReader(data);
    // huffman tree (16 codes, 8 maxbits, rle import with 4-bit entries)
    const lens = []; while (lens.length < 16) { let nb = br.read(4); if (nb !== 1) lens.push(nb); else { nb = br.read(4); if (nb === 1) lens.push(1); else { let rep = br.read(4) + 3; while (rep--) lens.push(nb); } } }
    if (lens.length !== 16) throw new Error('bad map tree');
    const lut = huffBuild(lens, 8);
    let rep = 0, last = 0;
    for (let i = 0; i < n; i++) {
      if (rep > 0) { this.mtype[i] = last; rep--; continue; }
      const v = huffDecode(lut, 8, br);
      if (v === 7) { this.mtype[i] = last; rep = 2 + huffDecode(lut, 8, br); }
      else if (v === 8) { this.mtype[i] = last; rep = 2 + 16 + (huffDecode(lut, 8, br) << 4); rep += huffDecode(lut, 8, br); }
      else this.mtype[i] = last = v;
    }
    let cur = firstoffs, lastSelf = 0, lastParent = 0;
    const raw = new Uint8Array(n * 12);
    for (let i = 0; i < n; i++) {
      let t = this.mtype[i], off = cur, len = 0, crc = 0;
      switch (t) {
        case 0: case 1: case 2: case 3: len = br.read(lb); cur += len; crc = br.read(16); break;
        case 4: len = hb; cur += len; crc = br.read(16); break;
        case 5: lastSelf = off = br.read(sb); break;
        case 6: off = br.read(pb); lastParent = off; break;
        case 10: lastSelf++; // fallthrough
        case 9: t = 5; off = lastSelf; break;
        case 11: t = 6; lastParent = off = i * hb / this.unitbytes; break;
        case 13: lastParent += hb / this.unitbytes; // fallthrough
        case 12: t = 6; off = lastParent; break;
      }
      this.mtype[i] = t; this.mlen[i] = len; this.moff[i] = off; this.mcrc[i] = crc;
      const r = i * 12; raw[r] = t; raw[r + 1] = len >>> 16; raw[r + 2] = len >>> 8; raw[r + 3] = len;
      const hi = Math.floor(off / 4294967296), lo = off >>> 0; raw[r + 4] = hi >>> 8; raw[r + 5] = hi; raw[r + 6] = lo >>> 24; raw[r + 7] = lo >>> 16; raw[r + 8] = lo >>> 8; raw[r + 9] = lo; raw[r + 10] = crc >>> 8; raw[r + 11] = crc;
    }
    if (crc16(raw) !== mapcrc) throw new Error('CHD map checksum mismatch (file damaged?)');
    for (let i = 0; i < n; i++) if (this.mtype[i] === 6) throw new Error('This CHD references a parent CHD; not supported.');
    this.mapLB = lb; this.mapSB = sb;
  }
  // decompress hunk i into dst (hunkbytes) given its compressed bytes
  decodeHunk(i, comp, dst) {
    const t = this.mtype[i], hb = this.hunkbytes;
    if (t === 4) { dst.set(comp.subarray(0, hb)); return; }
    const codec = this.codecs[t];
    const frames = this.fph;
    if (codec === 'cdlz' || codec === 'cdzl') {
      const eccb = (frames + 7) >> 3, clb = hb < 65536 ? 2 : 3, hdr = eccb + clb;
      let cb = (comp[eccb] << 8) | comp[eccb + 1]; if (clb > 2) cb = (cb << 8) | comp[eccb + 2];
      const tmp = this._tmp || (this._tmp = new Uint8Array(frames * SECT)), sub = this._sub || (this._sub = new Uint8Array(frames * 96));
      if (codec === 'cdlz') lzmaDecode(comp, hdr, hdr + cb, tmp, 0, frames * SECT); else INF(comp, hdr, hdr + cb, tmp, 0, frames * SECT);
      sub.fill(0); if (comp.length > hdr + cb) INF(comp, hdr + cb, comp.length, sub, 0, frames * 96);
      for (let f = 0; f < frames; f++) {
        dst.set(tmp.subarray(f * SECT, f * SECT + SECT), f * FRAME); dst.set(sub.subarray(f * 96, f * 96 + 96), f * FRAME + SECT);
        if (comp[f >> 3] & (1 << (f & 7))) eccGenerate(dst, f * FRAME);
      }
    } else if (codec === 'cdfl') {
      const tmp = this._tmp || (this._tmp = new Uint8Array(frames * SECT)), sub = this._sub || (this._sub = new Uint8Array(frames * 96));
      const end = flacDecode(comp, 0, comp.length, tmp, 0, frames * SECT / 4);
      sub.fill(0); if (comp.length > end) INF(comp, end, comp.length, sub, 0, frames * 96);
      for (let f = 0; f < frames; f++) { dst.set(tmp.subarray(f * SECT, f * SECT + SECT), f * FRAME); dst.set(sub.subarray(f * 96, f * 96 + 96), f * FRAME + SECT); }
    } else throw new Error('Unsupported CHD codec "' + codec + '" (only cdlz/cdzl/cdfl CD codecs are supported).');
  }
}

// ------------------------------------------------------------------ CHD writer helpers
class BitWriter {
  constructor() { this.out = []; this.acc = 0; this.n = 0; }
  write(v, k) { for (let i = k - 1; i >= 0; i--) { this.acc = (this.acc << 1) | (Math.floor(v / Math.pow(2, i)) & 1); if (++this.n === 8) { this.out.push(this.acc); this.acc = 0; this.n = 0; } } }
  bytes() { const o = this.out.slice(); if (this.n) o.push(this.acc << (8 - this.n)); return Uint8Array.from(o); }
}
// entries: [{type, len, crc, self}] in hunk order; types 0..4 (codec/none) or 5 (self)
function buildMap(entries, firstoffs, hunkbytes) {
  let maxlen = 1, maxself = 1;
  for (const e of entries) { if (e.type < 4) maxlen = Math.max(maxlen, e.len); if (e.type === 5) maxself = Math.max(maxself, e.self); }
  const lb = Math.max(1, Math.ceil(Math.log2(maxlen + 1))), sb = Math.max(1, Math.ceil(Math.log2(maxself + 1)));
  const bw = new BitWriter();
  bw.write(1, 4); bw.write(4, 4); bw.write(16 - 3, 4); // tree: 16 codes of length 4
  for (const e of entries) bw.write(e.type, 4);
  const raw = new Uint8Array(entries.length * 12); let cur = firstoffs;
  entries.forEach((e, i) => {
    let off = cur, len = 0, crc = 0;
    if (e.type < 4) { bw.write(e.len, lb); bw.write(e.crc, 16); len = e.len; crc = e.crc; cur += len; }
    else if (e.type === 4) { bw.write(e.crc, 16); len = hunkbytes; crc = e.crc; cur += len; }
    else { bw.write(e.self, sb); off = e.self; }
    const r = i * 12; raw[r] = e.type; raw[r + 1] = len >>> 16; raw[r + 2] = len >>> 8; raw[r + 3] = len;
    const hi = Math.floor(off / 4294967296), lo = off >>> 0; raw[r + 4] = hi >>> 8; raw[r + 5] = hi; raw[r + 6] = lo >>> 24; raw[r + 7] = lo >>> 16; raw[r + 8] = lo >>> 8; raw[r + 9] = lo; raw[r + 10] = crc >>> 8; raw[r + 11] = crc;
  });
  const body = bw.bytes(), hdr = new Uint8Array(16), dv = new DataView(hdr.buffer);
  dv.setUint32(0, body.length); dv.setUint16(4, Math.floor(firstoffs / 4294967296)); dv.setUint32(6, firstoffs >>> 0); dv.setUint16(10, crc16(raw));
  hdr[12] = lb; hdr[13] = sb; hdr[14] = 0;
  return [hdr, body];
}

if (typeof module !== 'undefined') module.exports = { crc32, crc32Combine, crc16, SHA1, INF, lzmaDecode, flacDecode, eccGenerate, CHD, buildMap, FRAME, SECT };
