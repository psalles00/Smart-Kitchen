const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require('/Users/pedrosalles/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=path.join(__dirname,'assets/screenshots');
const crops=[
 ['assistant','assistant-focus',{left:24,top:240,width:1158,height:1415}],
 ['recipe','recipe-ingredients',{left:48,top:1760,width:1110,height:862}],
 ['food-details','food-focus',{left:48,top:1080,width:1110,height:720}],
 ['market','pantry-focus',{left:25,top:455,width:1156,height:720}],
 ['recipes','recipes-focus',{left:48,top:455,width:1110,height:1260}],
 ['nutrition','nutrition-focus',{left:30,top:780,width:1146,height:1100}]
];
(async()=>{const manifest=[];for(const [src,dst,rect] of crops){const input=path.join(root,src+'.png');await sharp(input).extract(rect).png().toFile(path.join(root,dst+'.png'));manifest.push({source:src+'.png',crop:dst+'.png',rect,sourceSHA256:crypto.createHash('sha256').update(fs.readFileSync(input)).digest('hex')});}fs.writeFileSync(path.join(__dirname,'crop-sources.json'),JSON.stringify(manifest,null,2));})();
