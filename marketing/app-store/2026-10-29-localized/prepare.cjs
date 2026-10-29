const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const sharp=require('/Users/pedrosalles/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=__dirname,ocr='/Volumes/PS-Externo/Coding/Builds/Savoria-Nutrition-Final-20261028/marketing-recognize';
const labels={en:['Ingredients','Zucchini','Lists'],es:['Ingredientes','Calabacín','Listas'],fr:['Ingrédients','Courgette','Listes'],de:['Zutaten','Zucchini','Listen'],it:['Ingredienti','Zucchina','Liste'],ja:['材料','ズッキーニ','リスト']};
(async()=>{const provenance=[],checks=[];for(const language of process.argv.slice(2).length?process.argv.slice(2):Object.keys(labels)){
 const folder=path.join(root,'captures',language),files=['home','pantry','market','recipes','recipe','recipe-scrolled','nutrition'].map(n=>path.join(folder,n+'.png'));
 const cache=folder+'/recognized.json',existing=fs.existsSync(cache)?JSON.parse(fs.readFileSync(cache)):[],cacheTime=fs.existsSync(cache)?fs.statSync(cache).mtimeMs:0;const changed=files.filter(f=>fs.statSync(f).mtimeMs>cacheTime||!existing.some(r=>r.file===path.basename(f)));let records=existing;if(changed.length){const fresh=JSON.parse(cp.execFileSync(ocr,[language,...changed],{maxBuffer:8*1024*1024})),by=new Map(existing.map(r=>[r.file,r]));for(const r of fresh)by.set(r.file,r);records=[...by.values()];fs.writeFileSync(cache,JSON.stringify(records,null,2)+'\n');}
 const recipe=records.find(r=>r.file==='recipe-scrolled.png');const normalize=t=>t.normalize('NFKC').toLocaleLowerCase(language).replace(/[\s’']/g,'');
 const heading=recipe.lines.find(l=>normalize(l.text)===normalize(labels[language][0]));
 const last=recipe.lines.find(l=>normalize(l.text).includes(normalize(labels[language][1])));
 if(!heading||!last)throw Error('Missing ingredients boundaries: '+language);
 const top=Math.max(0,Math.floor(heading.top-14)),bottom=Math.min(recipe.height,Math.ceil(last.top+last.height+100));
 const crops=[['recipe-scrolled','recipe-ingredients',{left:48,top,width:1110,height:bottom-top}],['market','pantry-focus',{left:25,top:455,width:1156,height:720}],['recipes','recipes-focus',{left:48,top:455,width:1110,height:900}],['nutrition','nutrition-focus',{left:30,top:780,width:1146,height:1100}]];
 for(const [source,name,rect] of crops){const input=path.join(folder,source+'.png');await sharp(input).extract(rect).png().toFile(path.join(folder,name+'.png'));provenance.push({language,source:source+'.png',crop:name+'.png',rect,sourceSHA256:crypto.createHash('sha256').update(fs.readFileSync(input)).digest('hex')});}
 const breakfast={en:'Breakfast',es:'Desayuno',fr:'Petit-déjeuner',de:'Frühstück',it:'Colazione',ja:'朝食'};const gallery=records.find(r=>r.file==='recipes.png');const group=gallery.lines.find(l=>normalize(l.text)===normalize(breakfast[language])&&l.top>550&&l.top<800);if(!group)throw Error('Gallery section heading is not localized: '+language);
 const all=records.flatMap(r=>r.lines.map(l=>l.text)).join('\n');
 if(/caf[eé] da manh[ãa]|\bReceitas\b|\balmo[çc]o\b/i.test(all)||(language!=='es'&&/\bTodos\b|\bde \d+ ingredientes\b/.test(all)))throw Error('Portuguese UI remains: '+language);
 const pantry=records.find(r=>r.file==='pantry.png');if(!pantry.lines.some(l=>normalize(l.text)===normalize(labels[language][2])))throw Error('List title localization: '+language);
 checks.push({language,nativeUI:true,recipeHeading:heading.text,lastIngredient:last.text,galleryHeading:group.text,portugueseLeakCheck:'passed',screenshotCount:files.length});console.log('Prepared native captures and crops:',language);
 }
 fs.writeFileSync(root+'/crop-sources.json',JSON.stringify(provenance,null,2)+'\n');fs.writeFileSync(root+'/native-text-checks.json',JSON.stringify(checks,null,2)+'\n');
})().catch(e=>{console.error(e);process.exitCode=1});
