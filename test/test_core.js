const fs=require('fs');
const strip=s=>s.replace(/^if \(typeof module.*$/m,'');
const code=strip(fs.readFileSync(__dirname+'/../web/chd.js','utf8'))+strip(fs.readFileSync(__dirname+'/../web/core.js','utf8'))+';return {patchCHD,patchBIN,MD3,INF};';
const L=new Function(code)();
const [,, inFile, variant, fmt, outFile]=process.argv;
const fd=fs.openSync(inFile,'r');const size=fs.fstatSync(fd).size;
const src={size,read:(o,l)=>{const b=Buffer.alloc(l);fs.readSync(fd,b,0,l,o);return new Uint8Array(b.buffer,b.byteOffset,l);},slice:(o,l)=>({o,l})};
// node test_core.js <in.chd|bin> <variant> <chd|bin> <out> [patchdata dir]
const pd=process.argv[6]||(__dirname+'/../build/patchdata');
const z=new Uint8Array(Buffer.from(fs.readFileSync(pd+'/patch_'+variant+'.b64','utf8'),'base64'));
const t0=Date.now();
const isChd=fs.readFileSync(inFile,{encoding:null,flag:'r'}).subarray?null:null;
const h=Buffer.alloc(8);fs.readSync(fd,h,0,8,0);
const r=h.toString('latin1')==='MComprHD'?L.patchCHD(src,z,variant,fmt,null):L.patchBIN(src,z,variant,null);
console.log('filecrc',r.fileCrc.toString(16),r.fileSize);console.log('done',Date.now()-t0,'ms crc',r.crc.toString(16),'parts',r.parts.length);
const out=fs.openSync(outFile,'w');let w=0;
for(const p of r.parts){let b;if(p instanceof Uint8Array)b=p;else{b=Buffer.alloc(p.l);fs.readSync(fd,b,0,p.l,p.o);}fs.writeSync(out,b);w+=b.length;}
fs.closeSync(out);console.log('wrote',w);
