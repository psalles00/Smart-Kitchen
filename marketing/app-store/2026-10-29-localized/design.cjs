const fs=require('node:fs'),path=require('node:path');
const {locales,ui}=require('./locales.cjs');
const base=path.resolve(__dirname,'../2026-10-29-pt-BR');
function design(locale){
 const config=locales[locale];if(!config)throw Error('Unsupported marketing locale '+locale);
 let html=fs.readFileSync(base+'/index.html','utf8');
 // Longer literals first; generated screenshots and native captures remain separate.
 for(const [source,target] of Object.entries(ui[config.ui]).sort((a,b)=>b[0].length-a[0].length))html=source.length<=3?html.replaceAll("['"+source+"',","['"+target+"',"):html.replaceAll(source,target);
 const start=html.indexOf('const copy=['),end=html.indexOf('const COUNT=',start);
 html=html.slice(0,start)+'const copy='+JSON.stringify(config.pages)+';\n'+html.slice(end);
 html=html.replaceAll('assets/screenshots/${src}.png','/2026-10-29-localized/captures/'+config.ui+'/${src}.png')
  .replaceAll('assets/screenshots/nutrition-focus.png','/2026-10-29-localized/captures/'+config.ui+'/nutrition-focus.png')
  .replaceAll('assets/','/2026-10-29-pt-BR/assets/');
 html=html.replace('<html lang="pt-BR">','<html lang="'+locale+'">').replaceAll('Português brasileiro',config.name);
 const numberLocale={en:'en-US',es:'es-ES',fr:'fr-FR',de:'de-DE',it:'it-IT',ja:'ja-JP'}[config.ui];
 html=html.replace('function averageCard(){','const formatNumber=n=>new Intl.NumberFormat('+JSON.stringify(numberLocale)+').format(n);\nfunction averageCard(){')
  .replace('>1.880 <small>','>${formatNumber(1880)} <small>')
  .replace('<b>${d[1]}</b>','<b>${d[2]?formatNumber(Number(d[1].replace(".",""))):"—"}</b>');
 const cjk=locale==='ja'?'"Hiragino Sans",sans-serif':locale==='ko'?'"Apple SD Gothic Neo",sans-serif':locale==='zh-Hans'?'"PingFang SC","Hiragino Sans GB",sans-serif':null;
 const extra=`.copy h2,.copy p{white-space:nowrap}${cjk?'.copy h2,.copy p{font-family:'+cjk+';letter-spacing:-1px}.copy h2{line-height:1.15}':''}${config.ui==='ja'?'.objects{--display:"Hiragino Sans",sans-serif;--text:"Hiragino Sans",sans-serif}':''}${config.rtl?'.copy{direction:rtl;text-align:right!important}#page-2 .copy{width:950px}.copy h2,.copy p{font-family:"Geeza Pro",sans-serif;letter-spacing:0}.copy h2{line-height:1.15}':''}`;
 html=html.replace('</style>',extra+'\n</style>');
 const fit=`async function fitDesign(){if(!only)return;const copyEl=document.querySelector('.copy'),h=copyEl.querySelector('h2'),p=copyEl.querySelector('p');for(const [el,min] of [[h,90],[p,28]]){let n=parseFloat(getComputedStyle(el).fontSize);while(el.scrollWidth>el.clientWidth+1&&n>min){n--;el.style.fontSize=n+'px';}}let n=parseFloat(getComputedStyle(h).fontSize);while(copyEl.getBoundingClientRect().bottom>2760&&n>90){n--;h.style.fontSize=n+'px';}const ingredients=document.querySelector('.ingredient-panel');if(ingredients){const b=ingredients.getBoundingClientRect();ingredients.style.top=Math.min(1840,2770-b.height)+'px';}window.fitResult={headingSize:parseFloat(getComputedStyle(h).fontSize),subtitleSize:parseFloat(getComputedStyle(p).fontSize)};}`;
 html=html.replace('async function main(){',fit+'\nasync function main(){').replaceAll('await document.fonts.ready;window.designReady=true;','await document.fonts.ready;await fitDesign();window.designReady=true;');
 return html;
}
module.exports={design,locales,base};
