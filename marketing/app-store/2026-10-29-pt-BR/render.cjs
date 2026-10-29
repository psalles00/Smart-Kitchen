const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto');
const packages='/Users/pedrosalles/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/';
const {chromium}=require(packages+'playwright');
const sharp=require(packages+'sharp');
const root=__dirname;
const selected=(process.env.PAGES||'1,2,3,4,5,6,7,8,9').split(',').map(Number).filter(n=>n>=1&&n<=9);
(async()=>{
 const server=http.createServer((req,res)=>{const p=decodeURIComponent(new URL(req.url,'http://localhost').pathname),f=path.resolve(root,'.'+(p==='/'?'/index.html':p));if(!f.startsWith(root+path.sep)||!fs.existsSync(f)){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',f.endsWith('.html')?'text/html':f.endsWith('.png')?'image/png':f.endsWith('.svg')?'image/svg+xml':f.endsWith('.ttf')?'font/ttf':'text/plain');fs.createReadStream(f).pipe(res);});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const url='http://127.0.0.1:'+server.address().port;let browser;
 try{
  browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--enable-webgl','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  const page=await browser.newPage({viewport:{width:1320,height:2868},deviceScaleFactor:1});const failures=[];
  page.on('pageerror',e=>failures.push(e.message));
  fs.mkdirSync(root+'/png',{recursive:true});const checks=[],backgrounds=[];
  for(const i of selected){
   await page.goto(url+'/?page='+i);await page.waitForFunction(()=>window.designReady===true||window.renderErrors.length>0,{timeout:60000});
   const check=await page.evaluate(()=>({errors:window.renderErrors,fonts:[...document.fonts].map(f=>({family:f.family,status:f.status})),copy:[...document.querySelectorAll('.copy')].map(el=>{const b=el.getBoundingClientRect(),h=el.querySelector('h2');return {title:h.innerText,bottom:b.bottom,right:b.right,left:b.left,height:b.height,overflow:h.scrollWidth>h.clientWidth+1};}),images:[...document.querySelectorAll('img[data-native]')].map(im=>{const s=getComputedStyle(im);return {src:im.getAttribute('src'),naturalRatio:im.naturalWidth/im.naturalHeight,ratio:parseFloat(s.width)/parseFloat(s.height)};})}));
   if(check.errors.length||failures.length||check.fonts.some(f=>f.status!=='loaded')||check.copy.some(c=>c.overflow||c.bottom>2790||c.left<70||c.right>1250)||check.images.some(im=>Math.abs(im.naturalRatio-im.ratio)>.0001))throw Error('Layout: '+JSON.stringify(check));
   checks.push({page:i,...check});await sharp(await page.screenshot()).flatten({background:'#080302'}).removeAlpha().png().toFile(root+'/png/'+String(i).padStart(2,'0')+'.png');console.log('Exported',i);
   await page.addStyleTag({content:'.objects,.copy{visibility:hidden !important}'});
   backgrounds.push({page:i,buffer:await page.screenshot()});
  }
  if(backgrounds.length===9){const seams=[];for(let j=1;j<backgrounds.length;j++){const a=await sharp(backgrounds[j-1].buffer).extract({left:1319,top:0,width:1,height:2868}).removeAlpha().raw().toBuffer(),b=await sharp(backgrounds[j].buffer).extract({left:0,top:0,width:1,height:2868}).removeAlpha().raw().toBuffer();const diffs=Array.from(a,(v,k)=>Math.abs(v-b[k])).sort((a,b)=>a-b);const mean=diffs.reduce((a,b)=>a+b,0)/diffs.length;seams.push({between:[j,j+1],meanChannelDifference:mean,p99:diffs[Math.floor(diffs.length*.99)],maximum:diffs.at(-1)});if(mean>3||seams.at(-1).p99>12)throw Error('Background seam '+JSON.stringify(seams.at(-1)));}const bgLayers=[];for(let j=0;j<backgrounds.length;j++)bgLayers.push({input:await sharp(backgrounds[j].buffer).resize(264,574).toBuffer(),left:24+j*288,top:24});await sharp({create:{width:2616,height:622,channels:3,background:'#29231f'}}).composite(bgLayers).png().toFile(root+'/background-sequence.png');fs.writeFileSync(root+'/background-checks.json',JSON.stringify({worldWidth:11880,order:'1–9, contiguous absolute coordinates',seams},null,2)+'\n');}
  await page.setViewportSize({width:1140,height:1710});await page.goto(url);await page.waitForFunction(()=>window.designReady===true);
  await sharp(await page.screenshot({fullPage:true})).flatten({background:'#29231f'}).removeAlpha().png().toFile(root+'/preview.png');
  const layers=[],manifest=[];for(let i=1;i<=9;i++){const p=root+'/png/'+String(i).padStart(2,'0')+'.png';const m=await sharp(p).metadata();if(m.width!==1320||m.height!==2868||m.hasAlpha)throw Error('Invalid PNG '+i);const data=fs.readFileSync(p);manifest.push({page:i,path:'png/'+String(i).padStart(2,'0')+'.png',width:m.width,height:m.height,colorSpace:m.space,alpha:m.hasAlpha,bytes:data.length,sha256:crypto.createHash('sha256').update(data).digest('hex')});layers.push({input:await sharp(p).resize(264,574).toBuffer(),left:24+(i-1)*288,top:24});}
  await sharp({create:{width:2616,height:622,channels:3,background:'#29231f'}}).composite(layers).png().toFile(root+'/sequence.png');
  fs.writeFileSync(root+'/manifest.json',JSON.stringify({locale:'pt-BR',nativeDevice:'iPhone 17 Pro (Simulator)',screenshots:'production views with isolated demonstration data; page 02 illustrative chart; pages 04 and 06 authorized simplified interface demonstrations',pages:manifest},null,2)+'\n');
  if(checks.length){const old=fs.existsSync(root+'/render-checks.json')?JSON.parse(fs.readFileSync(root+'/render-checks.json')):[];const byPage=new Map(old.map(c=>[c.page,c]));for(const c of checks)byPage.set(c.page,c);fs.writeFileSync(root+'/render-checks.json',JSON.stringify([...byPage.values()].sort((a,b)=>a.page-b.page),null,2));}await browser.close();browser=null;
 }finally{if(browser)await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
