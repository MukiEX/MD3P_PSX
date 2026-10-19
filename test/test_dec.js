const fs=require('fs');const C=require('../web/chd.js');
const fn=process.argv[2];const fd=fs.openSync(fn,'r');const size=fs.fstatSync(fd).size;
const read=(o,l)=>{const b=Buffer.alloc(l);fs.readSync(fd,b,0,l,o);return new Uint8Array(b.buffer,b.byteOffset,l);};
const t0=Date.now();const chd=new C.CHD(read,size);
console.log(chd.codecs,chd.hunks,chd.tracks, Date.now()-t0,'ms map');
const cnt={};for(const t of chd.mtype)cnt[t]=(cnt[t]||0)+1;console.log(cnt);
const ref=fs.openSync(process.argv[3],'r');   // node test_dec.js <in.chd> <reference.bin>
const hb=chd.hunkbytes, nfr=+chd.tracks[0].FRAMES;
const cache=new Map(); const selfT=new Set();for(let i=0;i<chd.hunks;i++)if(chd.mtype[i]===5)selfT.add(chd.moff[i]);
console.log('self targets',selfT.size);
const sha=new C.SHA1();let crc=0,bad=0;const dst=new Uint8Array(hb);const rb=Buffer.alloc(8*2352);
for(let i=0;i<chd.hunks;i++){
  if(chd.mtype[i]===5)dst.set(cache.get(chd.moff[i]));
  else chd.decodeHunk(i,read(chd.moff[i],chd.mlen[i]),dst);
  if(selfT.has(i))cache.set(i,dst.slice());
  if(C.crc16(dst)!==chd.mcrc[i]&&chd.mtype[i]!==5){if(bad++<5)console.log('crc16 bad',i,chd.mtype[i]);}
  sha.update(dst);
  const f0=i*8,nf=Math.min(8,nfr-f0);
  if(nf>0){fs.readSync(ref,rb,0,nf*2352,f0*2352);for(let f=0;f<nf;f++){crc=C.crc32(crc,dst,f*2448,f*2448+2352);for(let k=0;k<2352;k++)if(rb[f*2352+k]!==dst[f*2448+k]){if(bad++<5)console.log('mismatch hunk',i,'frame',f,'byte',k,chd.mtype[i]);break;}}}
}
const raw=sha.digest();
console.log('time',Date.now()-t0,'crc',crc.toString(16),'bad',bad);
console.log('rawsha1',Buffer.from(raw).toString('hex'),Buffer.from(chd.hdr.subarray(64,84)).toString('hex'));
const hs=chd.meta.filter(m=>m.flags&1).map(m=>{const b=new Uint8Array(24);b.set(m.tag);b.set(new C.SHA1().update(m.data).digest(),4);return b;});
hs.sort((a,b)=>Buffer.compare(a,b));const o=new C.SHA1().update(raw);hs.forEach(h=>o.update(h));
console.log('sha1',Buffer.from(o.digest()).toString('hex'),Buffer.from(chd.hdr.subarray(84,104)).toString('hex'));
