// Outside-Beltway requests run directly in the visitor's browser.
// Contract recovered from the operator's supplied plan-your-trip.js (1.4.8).
const OUTSIDE66_CATALOG=/*OUTSIDE66*/{};
const OUTSIDE66_URL='https://ride66express.com/wp-content/themes/i66/theme-ajax.php';
const OUTSIDE66_NOTE='Ride66Express planner estimate for a standard E-ZPass vehicle. The operator describes these as historical-average estimates; realtime accuracy is not verified.';
let browser66Report=null,browser66Busy=false,outside66RequestToken=0;
function outside66Entries(dir){return OUTSIDE66_CATALOG[dir]||[];}
function outside66Exits(dir,entry){return(outside66Entries(dir).find(e=>e.id===entry)?.exits||[]).map((e,i)=>({...e,id:'o66:'+entry+':'+i}));}
function outside66Route(trip){
 if(trip.road==='66outside'){
  const exit=outside66Exits(trip.dir,trip.entry).find(e=>e.id===trip.exit);
  if(!exit)throw Error('No verified outside-Beltway route. Select the entry and exit again.');
  return{entry:trip.entry,gantries:exit.gantries,label:trip.entryLabel+' → '+exit.label};
 }
 if(!['Northbound','Southbound'].includes(trip.dir))throw Error('Unknown I-495 connection direction.');
 const entry=trip.dir==='Northbound'?'415':'414',key=trip.exit?.split(':')[1];
 const end={50:entry,monument:'420',stringfellow:'420',28:'420','29g':'420,423,425'}[key];
 if(!trip.exit?.startsWith('66w:')||!end)throw Error('No verified outside-Beltway connection.');
 return{entry,gantries:end,label:'I-495 '+(entry==='415'?'northbound':'southbound')+' Express → '+trip.exitLabel};
}
function outside66Form(route){
 if(!Object.values(OUTSIDE66_CATALOG).flat().some(e=>e.id===route.entry&&e.exits.some(x=>x.gantries===route.gantries)))throw Error('Unknown operator gantry pair.');
 const ends=route.gantries.split(',');
 return new URLSearchParams({action:'api_call','data[starting_gantry_id]':route.entry,'data[ending_gantry_id]':ends.at(-1),'data[middle_ending_gantry_id]':ends.length>=2?ends.at(-2):'','data[first_ending_gantry_id]':ends.length===3?ends[0]:'','data[xvWr]':'1','data[response]':''});
}
function outside66Amount(payload,route){
 if(payload?.success===false)throw Error(typeof payload.data?.error==='string'?payload.data.error.slice(0,240):'The operator could not quote this route.');
 let result=payload?.data?.curl_response;if(typeof result==='string'){try{result=JSON.parse(result);}catch{throw Error('Operator rate data is unreadable.');}}
 if(!Array.isArray(result?.rates))throw Error('The operator returned no rate list.');
 const ids=[...new Set([route.entry,...route.gantries.split(',')])],components=[];
 for(const id of ids){
  const rows=result.rates.filter(r=>String(r?.gantry?.gantryId)===id);
  if(!rows.length)throw Error('Rate missing for required I-66 gantry '+id+'. The full toll cannot be calculated.');
  // Match the operator's newest-rateEndDate selection. Keep the original date
  // strings for display; a date without an offset is not verified as fresh.
  const dated=rows.map(row=>({row,stamp:Date.parse(row.rateEndDate)}));
  if(dated.some(x=>!Number.isFinite(x.stamp)))throw Error('The operator returned an invalid rate timestamp for gantry '+id+'.');
  dated.sort((a,b)=>b.stamp-a.stamp);const row=dated[0].row,raw=row.gantry.vehicleClasses?.[0]?.rateAmountTag;
  if((typeof raw!=='number'&&typeof raw!=='string')||String(raw).trim()===''||!Number.isFinite(Number(raw))||Number(raw)<0)throw Error('The operator returned an invalid toll for gantry '+id+'.');
  components.push({gantry:id,price:Number(raw),rateEndDate:row.rateEndDate});
 }
 return{price:Math.round(components.reduce((sum,c)=>sum+c.price,0)*100)/100,outside66:true,outside66RateEnds:[...new Set(components.map(c=>c.rateEndDate))],components,note:OUTSIDE66_NOTE,dataSource:'Ride66Express planner via visitor browser'};
}
async function readOutside66Response(response){
 if(response.type==='opaque')throw Error('The operator response is unreadable.');
 if(Number(response.headers.get('content-length'))>2000000)throw Error('Operator response exceeds 2 MB.');
 const reader=response.body.getReader(),decoder=new TextDecoder();let bytes=0,body='';
 while(true){const part=await reader.read();if(part.done)break;bytes+=part.value.byteLength;if(bytes>2000000){await reader.cancel();throw Error('Operator response exceeds 2 MB.');}body+=decoder.decode(part.value,{stream:true});}
 return{bytes,body:body+decoder.decode()};
}
function renderBrowser66Report(report){
 browser66Report=report;
 document.getElementById('browser66-download').hidden=false;
 document.getElementById('browser66-details').hidden=false;
 document.getElementById('browser66-summary').textContent='Pricing report v3 · '+(report.status?'HTTP '+report.status+' · ':'')+report.outcome+' · '+report.route.label+' · '+new Date(report.completedAt).toLocaleTimeString();
}
async function fetchOutside66(route){
 const form=outside66Form(route),token=++outside66RequestToken,controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
 const report={version:3,requestedUrl:OUTSIDE66_URL,requestedAt:new Date().toISOString(),transport:'visitor-browser',credentials:'omit',route,requestBody:form.toString(),livePriceVerified:false};
 try{
  const response=await fetch(OUTSIDE66_URL,{method:'POST',body:form,mode:'cors',credentials:'omit',signal:controller.signal,referrerPolicy:'no-referrer'});
  report.status=response.status;report.responseType=response.type;report.contentType=response.headers.get('content-type')||'';
  Object.assign(report,await readOutside66Response(response));
  if(!response.ok)throw Error('Ride66Express returned HTTP '+response.status+'.');
  let payload;try{payload=JSON.parse(report.body);}catch{throw Error('Ride66Express returned a page instead of pricing JSON.');}
  const quote=outside66Amount(payload,route);report.outcome='estimate-received';report.estimate=quote;
  return{...quote,fetchedAt:new Date().toISOString()};
 }catch(error){
  report.outcome=controller.signal.aborted?'timeout':report.status?'operator-error':'browser-error';
  const message=controller.signal.aborted?'Ride66Express timed out after 15 seconds.':!report.status?'Your browser could not read Ride66Express pricing. CORS, networking, or operator blocking may be responsible.':error.message;
  report.error=message;throw Error(message);
 }finally{
  clearTimeout(timer);report.completedAt=new Date().toISOString();if(token===outside66RequestToken)renderBrowser66Report(report);
 }
}
async function fetchBrowser66(){
 if(browser66Busy)return;browser66Busy=true;
 const button=document.getElementById('browser66-test'),status=document.getElementById('browser66-status');button.disabled=true;button.textContent='Requesting toll…';
 try{
  const trip=typeof state!=='undefined'?state.trip:null;
  const route=trip&&(trip.road==='66outside'||trip.exit?.startsWith('66w:'))?outside66Route(trip):{entry:'415',gantries:'420',label:'Test route: I-495 northbound Express → Route 28'};
  status.textContent='Requesting '+route.label+' directly from your browser…';
  const quote=await fetchOutside66(route);
  status.textContent=route.label+': '+new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(quote.price)+' for the I-66 portion. Operator planner estimate; realtime accuracy is not verified. Download the pricing report to share the response.';
 }catch(error){status.textContent=error.message+' Download the pricing report for details.';}
 finally{browser66Busy=false;button.disabled=false;button.textContent='Try I-66 from this browser';}
}
document.getElementById('browser66-test').onclick=fetchBrowser66;
document.getElementById('browser66-download').onclick=()=>{
 if(!browser66Report)return;
 const url=URL.createObjectURL(new Blob([JSON.stringify(browser66Report,null,2)],{type:'application/json'})),link=document.createElement('a');
 link.href=url;link.download='i66-browser-report.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
};
