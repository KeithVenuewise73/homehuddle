/* FacilityHuddle — main.js
   Shared Supabase REST helpers + nav/footer injection, matching the
   pattern used by OrganizationHuddle and CoachesHuddle. */
const OH_SURL = 'https://urwnbskrtoplgnkkxuvl.supabase.co';
const OH_SKEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyd25ic2tydG9wbGdua2t4dXZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwNDgyMjMsImV4cCI6MjA5NDYyNDIyM30._BpvQsf6Ub5nwxY8jD3aGDLvyk0-_vBA4s6LREZ9ShQ';

async function ohGet(table, params={}) {
  const url = new URL(`${OH_SURL}/rest/v1/${table}`);
  Object.entries(params).forEach(([k,v])=>url.searchParams.set(k,v));
  const res = await fetch(url.toString(),{headers:{'apikey':OH_SKEY,'Authorization':`Bearer ${OH_SKEY}`}});
  if(!res.ok) throw new Error(await res.text());
  return res.json();
}
async function ohInsert(table, data) {
  const res = await fetch(`${OH_SURL}/rest/v1/${table}`,{method:'POST',headers:{'apikey':OH_SKEY,'Authorization':`Bearer ${OH_SKEY}`,'Content-Type':'application/json','Prefer':'return=representation'},body:JSON.stringify(data)});
  if(!res.ok) throw new Error(await res.text());
  return res.json();
}
async function ohUpdate(table, id, data) {
  const res = await fetch(`${OH_SURL}/rest/v1/${table}?id=eq.${id}`,{method:'PATCH',headers:{'apikey':OH_SKEY,'Authorization':`Bearer ${OH_SKEY}`,'Content-Type':'application/json','Prefer':'return=minimal'},body:JSON.stringify(data)});
  return res.ok;
}

function ohToast(msg,type='success'){
  let t=document.getElementById('oh-toast');
  if(!t){t=document.createElement('div');t.id='oh-toast';document.body.appendChild(t);}
  const colors={success:'background:#111;border:1px solid rgba(34,197,94,.4);color:#4ade80',error:'background:#111;border:1px solid rgba(239,68,68,.4);color:#f87171',info:'background:#111;border:1px solid rgba(124,58,237,.4);color:#c4b5fd'};
  t.style.cssText=`position:fixed;bottom:24px;right:24px;padding:12px 18px;border-radius:10px;font-size:13px;font-weight:600;z-index:9999;transform:translateY(0);opacity:1;transition:all .3s;pointer-events:none;font-family:'DM Sans',sans-serif;max-width:320px;${colors[type]||colors.success}`;
  t.textContent=msg;
  clearTimeout(t._to);
  t._to=setTimeout(()=>{t.style.opacity='0';},3500);
}

function ohAlert(id,msg,type='success'){
  const el=document.getElementById(id);if(!el)return;
  el.textContent=msg;el.className=`oh-alert ${type}`;el.style.display='block';
  el.scrollIntoView({behavior:'smooth',block:'nearest'});
}

function ohParam(name){return new URLSearchParams(window.location.search).get(name);}

function ohInjectNav(active=''){
  const links=[
    {href:'index.html',label:'Home'},
    {href:'dashboard.html',label:'Dashboard'},
  ];
  document.body.insertAdjacentHTML('afterbegin',`
  <nav class="oh-nav">
    <a href="index.html" class="oh-nav-brand">
      <div class="oh-nav-logo">Facility<span>Huddle</span></div>
      <div class="oh-nav-powered">POWERED BY <a href="https://venuewise.net">VENUEWISE</a></div>
    </a>
    <div class="oh-nav-links">
      ${links.map(l=>`<a href="${l.href}" ${active===l.label?'style="color:var(--white)"':''}>${l.label}</a>`).join('')}
    </div>
  </nav>`);
}

function ohInjectFooter(){
  document.body.insertAdjacentHTML('beforeend',`
  <div class="eco-bar">
    <div class="eco-bar-inner">
      <span class="eco-bar-text">★ <strong>Venuewise Ecosystem</strong> — One connected platform for sports families</span>
      <div class="eco-bar-links">
        <a href="https://venuewise.net/homehuddle/">HomeHuddle</a>
        <a href="https://venuewise.net/homehuddle/family--athlete.html">AthleteHuddle</a>
        <a href="https://venuewise.net/homehuddle/coacheshuddle/">CoachesHuddle</a>
        <a href="https://venuewise.net/homehuddle/organizationhuddle/">OrganizationHuddle</a>
        <a href="index.html" class="active">FacilityHuddle</a>
        <a href="https://5starsportsmedia.com" style="color:var(--gold);font-weight:700">5-Star Sports Media ↗</a>
      </div>
    </div>
  </div>`);
  document.querySelectorAll('.yr').forEach(el=>el.textContent=new Date().getFullYear());
}
