const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto');
const packages='/Users/pedrosalles/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/';
const {chromium}=require(packages+'playwright'),sharp=require(packages+'sharp');
const {design,locales,base}=require('./design.cjs');
const root=__dirname,webRoot=path.dirname(root),all=['pt-BR',...Object.keys(locales)];
const selected=(process.env.LOCALES||Object.keys(locales).join(',')).split(',');
const pages=(process.env.PAGES||'1,2,3,4,5,6,7,8,9').split(',').map(Number).filter(n=>n>=1&&n<=9);
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const server=http.createServer((req,res)=>{const u=new URL(req.url,'http://localhost');if(u.pathname.endsWith('/design.html')){try{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(design(u.searchParams.get('locale')));}catch(e){res.writeHead(500);res.end(String(e));}return;}const file=path.resolve(webRoot,'.'+decodeURIComponent(u.pathname));if(!file.startsWith(webRoot+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',file.endsWith('.png')?'image/png':file.endsWith('.svg')?'image/svg+xml':file.endsWith('.ttf')?'font/ttf':'text/plain; charset=utf-8');fs.createReadStream(file).pipe(res);});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
 try{
 browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--enable-webgl','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1320,height:2868},deviceScaleFactor:1});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const url='http://127.0.0.1:'+server.address().port+'/2026-10-29-localized/design.html';
 for(const locale of selected){
  if(!locales[locale])throw Error('Unknown locale '+locale);const config=locales[locale],folder=path.join(root,locale);fs.mkdirSync(folder+'/png',{recursive:true});
  const checks=[];
  for(const i of pages){
   await page.goto(url+'?locale='+locale+'&page='+i);await page.waitForFunction(()=>window.designReady===true||window.renderErrors.length>0,{timeout:60000});
   await page.evaluate(()=>Promise.all([document.fonts.load('700 100px Bricolage'),document.fonts.load('400 40px Inter')]));
   const check=await page.evaluate(()=>{const el=document.querySelector('.copy'),h=el.querySelector('h2'),p=el.querySelector('p'),b=el.getBoundingClientRect();return {errors:window.renderErrors,fonts:[...document.fonts].map(f=>({family:f.family,status:f.status})),fit:window.fitResult,heading:h.innerText,subtitle:p.innerText,copy:{left:b.left,right:b.right,bottom:b.bottom,overflow:h.scrollWidth>h.clientWidth+1||p.scrollWidth>p.clientWidth+1},panels:[...document.querySelectorAll('.average-card,.ideas-demo,.capture-photo,.capture-text,.capture-voice,.social-flow,.ingredient-panel')].map(e=>{const b=e.getBoundingClientRect();return{type:e.className,left:b.left,right:b.right,bottom:b.bottom};}),screenshots:[...document.querySelectorAll('img[data-native]')].map(im=>{const s=getComputedStyle(im);return{src:im.getAttribute('src'),naturalRatio:im.naturalWidth/im.naturalHeight,ratio:parseFloat(s.width)/parseFloat(s.height)};})};});
   if(errors.length||check.errors.length||check.fonts.some(f=>f.status==='error')||check.copy.overflow||check.copy.left<65||check.copy.right>1255||check.copy.bottom>2790||check.panels.some(p=>p.left<55||p.right>1265||p.bottom>2800)||check.screenshots.some(im=>Math.abs(im.naturalRatio-im.ratio)>.0001||!im.src.includes('/captures/'+config.ui+'/')))throw Error(locale+' page '+i+' '+JSON.stringify({errors,check}));
   checks.push({page:i,...check});await sharp(await page.screenshot()).flatten({background:'#080302'}).removeAlpha().png().toFile(folder+'/png/'+String(i).padStart(2,'0')+'.png');
  }
  const old=fs.existsSync(folder+'/checks.json')?JSON.parse(fs.readFileSync(folder+'/checks.json')):[];const by=new Map(old.map(c=>[c.page,c]));for(const c of checks)by.set(c.page,c);fs.writeFileSync(folder+'/checks.json',JSON.stringify([...by.values()].sort((a,b)=>a.page-b.page),null,2)+'\n');
  if(Array.from({length:9},(_,i)=>folder+'/png/'+String(i+1).padStart(2,'0')+'.png').every(fs.existsSync)){
   const layers=[],strip=[],manifest=[];
   for(let i=1;i<=9;i++){const file=folder+'/png/'+String(i).padStart(2,'0')+'.png',data=fs.readFileSync(file),m=await sharp(data).metadata();if(m.width!==1320||m.height!==2868||m.hasAlpha)throw Error('PNG '+file);layers.push({input:await sharp(data).resize(330,717).toBuffer(),left:36+((i-1)%3)*354,top:100+Math.floor((i-1)/3)*741});strip.push({input:await sharp(data).resize(264,574).toBuffer(),left:24+(i-1)*288,top:24});manifest.push({page:i,file:'png/'+String(i).padStart(2,'0')+'.png',width:m.width,height:m.height,colorSpace:m.space,alpha:m.hasAlpha,bytes:data.length,sha256:digest(data)});}
   const title=Buffer.from('<svg width="1110" height="70"><text x="36" y="42" fill="#eee8e3" font-family="Arial" font-size="25">Savoria · '+locale+' · UI: '+config.ui+'</text></svg>');
   await sharp({create:{width:1110,height:2347,channels:3,background:'#29231f'}}).composite([{input:title,left:0,top:0},...layers]).png().toFile(folder+'/preview.png');
   await sharp({create:{width:2616,height:622,channels:3,background:'#29231f'}}).composite(strip).png().toFile(folder+'/sequence.png');
   fs.writeFileSync(folder+'/manifest.json',JSON.stringify({locale,interfaceLanguage:config.ui,usesEnglishFallback:config.ui==='en'&&locale!=='en-US',nativeScreenshots:true,rtlPromotionalCopy:!!config.rtl,backgroundSourceSHA256:digest(fs.readFileSync(base+'/assets/sunset.glsl')),pages:manifest},null,2)+'\n');
   fs.writeFileSync(folder+'/copy.md','# Savoria — '+config.name+'\n\nInterface: '+config.ui+'\n\n'+config.pages.map((c,i)=>'## '+String(i+1).padStart(2,'0')+'\n\n'+c.map(x=>x.replaceAll('<br>','\n')).join('\n\n')).join('\n\n')+'\n');
  }
  console.log('Rendered and checked:',locale,'UI:',config.ui,'pages:',pages.join(','));
 }
 const pt=path.join(root,'pt-BR');fs.mkdirSync(pt+'/png',{recursive:true});for(let i=1;i<=9;i++){const file='png/'+String(i).padStart(2,'0')+'.png';fs.copyFileSync(base+'/'+file,pt+'/'+file);}for(const file of ['preview.png','sequence.png','manifest.json','copy.md'])fs.copyFileSync(base+'/'+file,pt+'/'+file);
 if(all.every(l=>fs.existsSync(path.join(root,l,'preview.png')))){
  const layers=[];for(let i=0;i<all.length;i++){const file=path.join(root,all[i],'png/01.png');layers.push({input:await sharp(file).resize(264,574).toBuffer(),left:24+(i%5)*288,top:64+Math.floor(i/5)*640});const label=Buffer.from('<svg width="264" height="42"><text x="0" y="30" fill="#eee8e3" font-family="Arial" font-size="22">'+all[i]+'</text></svg>');layers.push({input:label,left:24+(i%5)*288,top:24+Math.floor(i/5)*640});}
  await sharp({create:{width:1464,height:1310,channels:3,background:'#29231f'}}).composite(layers).png().toFile(root+'/overview.png');
  fs.writeFileSync(root+'/index.html','<!doctype html><meta charset="utf-8"><title>Savoria · 10 idiomas</title><style>body{background:#29231f;color:#eee8e3;font:18px system-ui;padding:30px}main{display:flex;flex-wrap:wrap;gap:30px}article{width:330px}img{width:330px}a{color:#f4a15d}</style><h1>Savoria · 10 idiomas · 90 imagens</h1><main>'+all.map(l=>'<article><h2>'+l+'</h2><p>Interface: '+(l==='pt-BR'?'pt-BR':locales[l].ui)+'</p><a href="'+l+'/preview.png"><img src="'+l+'/preview.png"></a><p><a href="'+l+'/png/">PNGs</a> · <a href="'+l+'/sequence.png">Sequência</a> · <a href="'+l+'/copy.md">Textos</a></p></article>').join('')+'</main>');
 }
 await browser.close();browser=null;
 }finally{if(browser)await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
