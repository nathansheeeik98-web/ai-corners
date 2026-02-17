#!/data/data/com.termux/files/usr/bin/bash
set -e

node - <<'NODE'
const fs = require("fs");
const p = "public/index.html";
let html = fs.readFileSync(p, "utf8");

function ensureContains(needle, insertBeforeRegex, content) {
  if (html.includes(needle)) return;
  html = html.replace(insertBeforeRegex, content + "\n$&");
}

function replacePage(pageName, innerHtml) {
  const re = new RegExp(`(<div\\s+class="page"[^>]*data-page="${pageName}"[^>]*>)([\\s\\S]*?)(<\\/div>)`, "i");
  if (re.test(html)) {
    html = html.replace(re, `$1\n${innerHtml}\n$3`);
    return true;
  }
  return false;
}

// 1) Garante que existe app shell com pages
if (!html.includes('data-page="ao-vivo"') || !html.includes('class="tabs"')) {
  console.error("❌ Não encontrei o app shell (pages/tabs). Rode o script do layout mobile antes.");
  process.exit(1);
}

// 2) CSS de listas/cards mobile (se não existir)
ensureContains('id="fill5-ui-css"', /<\/head>/i, `
<style id="fill5-ui-css">
  .rc-grid{ display:grid; gap:10px; }
  .rc-card{ padding:14px; border-radius: var(--r,18px); }
  .rc-title{ font-size:14px; font-weight:900; margin:0 0 6px; }
  .rc-sub{ font-size:12px; color: rgba(255,255,255,.68); margin:0 0 10px; }
  .rc-row{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
  .rc-row > *{ flex:1; min-width:120px; }
  .rc-kpi{ background: rgba(255,255,255,.06); border:1px solid rgba(255,255,255,.10); border-radius:16px; padding:10px; }
  .rc-kpi b{ display:block; font-size:14px; }
  .rc-kpi span{ display:block; font-size:11px; color: rgba(255,255,255,.65); margin-top:2px; }
  .rc-actions{ display:flex; gap:8px; margin-top:10px; }
  .rc-actions button{ flex:1; }
  .rc-mini{ font-size:12px; color: rgba(255,255,255,.72); }
  .rc-divider{ height:1px; background: rgba(255,255,255,.08); margin:10px 0; }
  .rc-pill{ display:inline-flex; gap:6px; align-items:center; border:1px solid rgba(255,255,255,.10); background: rgba(255,255,255,.06); padding:6px 10px; border-radius:999px; font-size:12px; }
  .rc-pill i{ width:8px; height:8px; border-radius:999px; background:#3cff7a; display:inline-block; }
  .rc-danger i{ background:#ff6b6b; }
  .rc-warn i{ background:#ffd36a; }
  .rc-btn-ghost{ background: rgba(255,255,255,.06) !important; border:1px solid rgba(255,255,255,.10) !important; }
  .rc-btn-red{ background: linear-gradient(180deg, var(--red,#E10600), var(--red2,#B80000)) !important; }
  .rc-input{ width:100%; }
  .rc-list{ display:grid; gap:10px; }
</style>
`);

// 3) Conteúdo das 5 telas
const aoVivo = `
<div class="rc-grid">
  <div class="card rc-card">
    <div class="rc-row" style="justify-content:space-between">
      <div>
        <div class="rc-title">Ao vivo</div>
        <div class="rc-sub">Mostra os 3 jogos monitorados + analisar em 1 toque.</div>
      </div>
      <div style="text-align:right">
        <span class="rc-pill" id="rc-status"><i></i><span class="rc-mini">online</span></span>
      </div>
    </div>

    <div class="rc-actions">
      <button class="btn2" id="btn-refresh-live">Atualizar</button>
      <button class="btn" id="btn-analyze-all">Analisar todos</button>
    </div>
  </div>

  <div class="rc-list" id="live-list">
    <div class="card rc-card"><div class="rc-sub">Sem dados ainda. Vá em <b>Monitor</b> e coloque 1–3 Fixture IDs.</div></div>
  </div>

  <div class="card rc-card">
    <div class="rc-title">Última recomendação</div>
    <pre id="out" style="margin:0">Clique em “Analisar” em algum jogo.</pre>
  </div>
</div>
`;

const melhores = `
<div class="rc-grid">
  <div class="card rc-card">
    <div class="rc-title">Melhores (Ranking)</div>
    <div class="rc-sub">Classifica os jogos monitorados pelo “confianca” do /api/analyze.</div>
    <div class="rc-actions">
      <button class="btn2" id="btn-refresh-rank">Atualizar ranking</button>
      <button class="btn rc-btn-red" id="btn-rank-now">Rankear agora</button>
    </div>
  </div>

  <div class="rc-list" id="rank-list">
    <div class="card rc-card"><div class="rc-sub">Sem ranking ainda. Clique em <b>Rankear agora</b>.</div></div>
  </div>
</div>
`;

const favoritos = `
<div class="rc-grid">
  <div class="card rc-card">
    <div class="rc-title">Favoritos</div>
    <div class="rc-sub">Salva Fixture IDs (top 3 favoritos pode virar seu Monitor em 1 clique).</div>
    <div class="rc-actions">
      <button class="btn2" id="btn-fav-reload">Recarregar</button>
      <button class="btn" id="btn-fav-apply-monitor">Usar top 3 como Monitor</button>
    </div>
  </div>

  <div class="rc-list" id="fav-list">
    <div class="card rc-card"><div class="rc-sub">Ainda sem favoritos. Vá em <b>Ao vivo</b> e clique ⭐.</div></div>
  </div>
</div>
`;

const monitor = `
<div class="rc-grid">
  <div class="card rc-card">
    <div class="rc-title">Monitor (3 jogos)</div>
    <div class="rc-sub">Cole até 3 Fixture IDs da API-Football. Atualização manual + auto (Config).</div>

    <div class="rc-row">
      <div>
        <label class="rc-mini">Fixture #1</label>
        <input class="rc-input" id="fx1" placeholder="Ex: 123456" />
      </div>
      <div>
        <label class="rc-mini">Fixture #2</label>
        <input class="rc-input" id="fx2" placeholder="Ex: 234567" />
      </div>
      <div>
        <label class="rc-mini">Fixture #3</label>
        <input class="rc-input" id="fx3" placeholder="Ex: 345678" />
      </div>
    </div>

    <div class="rc-actions">
      <button class="btn2" id="btn-load-monitor">Carregar atuais</button>
      <button class="btn rc-btn-red" id="btn-save-monitor">Salvar monitor</button>
    </div>

    <div class="rc-divider"></div>
    <div class="rc-mini">
      Dica: no seu servidor você usa /api/live/set-fixtures e /api/live/snapshots.
    </div>
  </div>

  <div class="card rc-card">
    <div class="rc-title">Snapshots (bruto)</div>
    <pre id="snap" style="margin:0">Clique em “Carregar atuais” ou “Salvar monitor”.</pre>
  </div>
</div>
`;

const config = `
<div class="rc-grid">
  <div class="card rc-card">
    <div class="rc-title">Config</div>
    <div class="rc-sub">Controle de atualização, alertas e vibração.</div>

    <div class="rc-row">
      <div class="rc-kpi">
        <b>Auto refresh</b>
        <span>Minutos (padrão 10)</span>
        <input class="rc-input" id="cfg-refresh-min" type="number" min="1" max="60" value="10"/>
      </div>
      <div class="rc-kpi">
        <b>Alerta mínimo</b>
        <span>Confianca pra acender badge</span>
        <input class="rc-input" id="cfg-alert-min" type="number" min="50" max="95" value="80"/>
      </div>
    </div>

    <div class="rc-row" style="margin-top:10px">
      <div class="rc-kpi">
        <b>Haptic</b>
        <span>Vibração nos tabs</span>
        <select class="rc-input" id="cfg-haptic">
          <option value="on" selected>Ligado</option>
          <option value="off">Desligado</option>
        </select>
      </div>
      <div class="rc-kpi">
        <b>Modo</b>
        <span>Economiza API</span>
        <select class="rc-input" id="cfg-economy">
          <option value="on" selected>Econômico</option>
          <option value="off">Agressivo</option>
        </select>
      </div>
    </div>

    <div class="rc-actions" style="margin-top:10px">
      <button class="btn2" id="btn-cfg-reset">Reset</button>
      <button class="btn rc-btn-red" id="btn-cfg-save">Salvar</button>
    </div>

    <div class="rc-divider"></div>
    <div class="rc-mini" id="cfg-status">—</div>
  </div>
</div>
`;

// aplica conteúdo
const ok1 = replacePage("ao-vivo", aoVivo);
const ok2 = replacePage("melhores", melhores);
const ok3 = replacePage("favoritos", favoritos);
const ok4 = replacePage("monitor", monitor);
const ok5 = replacePage("config", config);

if (![ok1,ok2,ok3,ok4,ok5].every(Boolean)) {
  console.error("❌ Não consegui localizar todas as páginas data-page no HTML.");
  process.exit(1);
}

// 4) JS principal (uma vez só)
const mainScriptId = "fill5-main-js";
if (!html.includes(`id="${mainScriptId}"`)) {
  html = html.replace(/<\/body>/i, `
<script id="${mainScriptId}">
(function(){
  const $ = (id) => document.getElementById(id);

  // ===== Storage =====
  const S = {
    get refreshMin(){ return Number(localStorage.getItem("refreshMin") || "10"); },
    set refreshMin(v){ localStorage.setItem("refreshMin", String(v)); },

    get alertMin(){ return Number(localStorage.getItem("alertMin") || "80"); },
    set alertMin(v){ localStorage.setItem("alertMin", String(v)); },

    get haptic(){ return localStorage.getItem("haptic") || "on"; },
    set haptic(v){ localStorage.setItem("haptic", v); },

    get economy(){ return localStorage.getItem("economy") || "on"; },
    set economy(v){ localStorage.setItem("economy", v); },

    get favs(){
      try { return JSON.parse(localStorage.getItem("favs") || "[]"); } catch(e){ return []; }
    },
    set favs(arr){ localStorage.setItem("favs", JSON.stringify(arr || [])); }
  };

  async function hapticLight(){
    if (S.haptic === "off") return;
    try{
      if (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Haptics){
        await window.Capacitor.Plugins.Haptics.impact({ style: "LIGHT" });
        return;
      }
    }catch(e){}
    try{ if (navigator.vibrate) navigator.vibrate(10); }catch(e){}
  }

  // ===== API =====
  async function api(path, opts){
    const r = await fetch(path, opts);
    const t = await r.text();
    try { return JSON.parse(t); } catch(e){ return { raw:t, ok:false }; }
  }

  // ===== Render helpers =====
  function cardForSnap(s){
    const favs = S.favs;
    const isFav = favs.includes(String(s.fixture_id));
    const title = (s.match || "Jogo").replace(" vs ", "  •  ");
    return \`
      <div class="card rc-card">
        <div class="rc-row" style="justify-content:space-between">
          <div>
            <div class="rc-title">\${title}</div>
            <div class="rc-sub">Min: \${s.minute} • Placar: \${s.score} • Fixture: \${s.fixture_id}</div>
          </div>
          <div style="text-align:right">
            <button class="btn2 rc-btn-ghost" data-fav="\${s.fixture_id}" title="Favoritar">\${isFav ? "★" : "☆"}</button>
          </div>
        </div>

        <div class="rc-row">
          <div class="rc-kpi"><b>\${s.corners_total}</b><span>Escanteios (T)</span></div>
          <div class="rc-kpi"><b>\${s.corners_home}/\${s.corners_away}</b><span>Esc (M/V)</span></div>
          <div class="rc-kpi"><b>\${s.shots_total}</b><span>Chutes (T)</span></div>
          <div class="rc-kpi"><b>\${s.shots_on_target}</b><span>No alvo</span></div>
        </div>

        <div class="rc-actions">
          <button class="btn2" data-analyze="\${s.fixture_id}">Analisar</button>
          <button class="btn rc-btn-red" data-open-monitor="\${s.fixture_id}">Mandar pro Monitor</button>
        </div>
      </div>\`;
  }

  function setStatus(ok){
    const el = $("rc-status");
    if(!el) return;
    el.classList.toggle("rc-danger", !ok);
    el.querySelector("span")?.remove?.();
    const sp = document.createElement("span");
    sp.className = "rc-mini";
    sp.textContent = ok ? "online" : "offline";
    el.appendChild(sp);
  }

  // ===== Live =====
  let latestSnapshots = []; // array of snap.data
  async function refreshLive(){
    try{
      const j = await api("/api/live/snapshots");
      const items = Array.isArray(j.items) ? j.items : [];
      latestSnapshots = items.map(x => x?.data).filter(Boolean);

      $("snap") && ($("snap").textContent = JSON.stringify(j, null, 2));
      setStatus(true);

      const list = $("live-list");
      if(list){
        if(!latestSnapshots.length){
          list.innerHTML = \`<div class="card rc-card"><div class="rc-sub">Sem dados. Vá em <b>Monitor</b> e cole Fixture IDs.</div></div>\`;
        } else {
          list.innerHTML = latestSnapshots.map(cardForSnap).join("");
        }
      }

      hookLiveButtons();
      updateBadges();
    }catch(e){
      setStatus(false);
    }
  }

  function hookLiveButtons(){
    // favoritar
    document.querySelectorAll("[data-fav]").forEach(btn=>{
      btn.onclick = async () => {
        await hapticLight();
        const id = String(btn.getAttribute("data-fav"));
        const favs = new Set(S.favs.map(String));
        if (favs.has(id)) favs.delete(id); else favs.add(id);
        S.favs = Array.from(favs);
        refreshFavs();
        refreshLive();
      };
    });

    // analisar
    document.querySelectorAll("[data-analyze]").forEach(btn=>{
      btn.onclick = async () => {
        await hapticLight();
        const id = String(btn.getAttribute("data-analyze"));
        const snap = latestSnapshots.find(x => String(x.fixture_id) === id);
        if(!snap) return;
        $("out").textContent = "Analisando...";
        const res = await api("/api/analyze", {
          method:"POST",
          headers:{ "Content-Type":"application/json" },
          body: JSON.stringify({
            minute: snap.minute,
            score: snap.score,
            corners_home: snap.corners_home,
            corners_away: snap.corners_away,
            corners_total: snap.corners_total,
            shots_total: snap.shots_total,
            shots_on_target: snap.shots_on_target,
            pressure_side: snap.pressure_side,
            red_cards: snap.red_cards,
            notes: \`RedCorner IA | \${snap.match} | fixture \${snap.fixture_id}\`
          })
        });
        const result = res.result || res.heuristic || res;
        $("out").textContent = JSON.stringify(result, null, 2);
        updateBadges(result);
      };
    });

    // mandar pro monitor: coloca no fx1 se vazio, senão fx2, fx3
    document.querySelectorAll("[data-open-monitor]").forEach(btn=>{
      btn.onclick = async () => {
        await hapticLight();
        const id = String(btn.getAttribute("data-open-monitor"));
        const a = [$("fx1"),$("fx2"),$("fx3")].filter(Boolean);
        for (const inp of a){
          if (!inp.value.trim()){ inp.value = id; break; }
        }
        // troca pra tab monitor (se existir tab)
        const t = document.querySelector('.tabbtn[data-tab="monitor"]');
        t && t.click();
      };
    });
  }

  async function analyzeAll(){
    if(!latestSnapshots.length) return;
    for (const s of latestSnapshots){
      // economia: só analisa 1 por vez e pausa levemente
      await api("/api/analyze", {
        method:"POST",
        headers:{ "Content-Type":"application/json" },
        body: JSON.stringify({
          minute: s.minute, score: s.score,
          corners_home:s.corners_home, corners_away:s.corners_away, corners_total:s.corners_total,
          shots_total:s.shots_total, shots_on_target:s.shots_on_target,
          pressure_side:s.pressure_side, red_cards:s.red_cards,
          notes: \`RedCorner IA | \${s.match} | fixture \${s.fixture_id}\`
        })
      });
      if (S.economy === "on") await new Promise(r=>setTimeout(r, 250));
    }
    // atualiza ranking depois
    await refreshRank();
  }

  // ===== Ranking =====
  async function refreshRank(){
    const list = $("rank-list");
    if(!list) return;

    if(!latestSnapshots.length){
      list.innerHTML = \`<div class="card rc-card"><div class="rc-sub">Sem snapshots. Vá em <b>Ao vivo</b> e clique Atualizar.</div></div>\`;
      return;
    }

    list.innerHTML = \`<div class="card rc-card"><div class="rc-sub">Calculando ranking...</div></div>\`;

    const scored = [];
    for (const s of latestSnapshots){
      const res = await api("/api/analyze", {
        method:"POST",
        headers:{ "Content-Type":"application/json" },
        body: JSON.stringify({
          minute: s.minute, score: s.score,
          corners_home:s.corners_home, corners_away:s.corners_away, corners_total:s.corners_total,
          shots_total:s.shots_total, shots_on_target:s.shots_on_target,
          pressure_side:s.pressure_side, red_cards:s.red_cards,
          notes: \`Ranking | \${s.match} | fixture \${s.fixture_id}\`
        })
      });
      const r = res.result || res.heuristic || res;
      scored.push({ snap:s, r });
      if (S.economy === "on") await new Promise(r=>setTimeout(r, 200));
    }

    scored.sort((a,b)=> (Number(b.r?.confianca)||0) - (Number(a.r?.confianca)||0));

    list.innerHTML = scored.map(({snap, r}, idx) => {
      const conf = Number(r?.confianca)||0;
      const acao = r?.acao || "—";
      const linha = r?.linha_sugerida || "—";
      return \`
      <div class="card rc-card">
        <div class="rc-row" style="justify-content:space-between">
          <div>
            <div class="rc-title">#\${idx+1} • \${(snap.match||"Jogo").replace(" vs ","  •  ")}</div>
            <div class="rc-sub">Min \${snap.minute} • \${snap.score} • Fixture \${snap.fixture_id}</div>
          </div>
          <div style="text-align:right">
            <span class="rc-pill \${conf>=S.alertMin ? "" : "rc-warn"}"><i></i><span class="rc-mini">\${conf}%</span></span>
          </div>
        </div>
        <div class="rc-row">
          <div class="rc-kpi"><b>\${acao}</b><span>Ação</span></div>
          <div class="rc-kpi"><b>\${linha}</b><span>Linha</span></div>
          <div class="rc-kpi"><b>\${snap.corners_total}</b><span>Esc (T)</span></div>
          <div class="rc-kpi"><b>\${snap.shots_total}</b><span>Chutes</span></div>
        </div>
        <div class="rc-actions">
          <button class="btn2" data-analyze="\${snap.fixture_id}">Ver análise</button>
          <button class="btn rc-btn-red" data-open-monitor="\${snap.fixture_id}">Mandar pro Monitor</button>
        </div>
      </div>\`;
    }).join("");

    hookLiveButtons();
    updateBadges(scored[0]?.r);
  }

  // ===== Favoritos =====
  function refreshFavs(){
    const list = $("fav-list");
    if(!list) return;
    const favs = S.favs.map(String);

    if(!favs.length){
      list.innerHTML = \`<div class="card rc-card"><div class="rc-sub">Sem favoritos. Vá em <b>Ao vivo</b> e clique ☆.</div></div>\`;
      return;
    }

    list.innerHTML = favs.map((id, i) => \`
      <div class="card rc-card">
        <div class="rc-row" style="justify-content:space-between">
          <div>
            <div class="rc-title">Fixture \${id}</div>
            <div class="rc-sub">Posição: #\${i+1}</div>
          </div>
          <div style="text-align:right">
            <button class="btn2 rc-btn-ghost" data-fav-remove="\${id}">Remover</button>
          </div>
        </div>
        <div class="rc-actions">
          <button class="btn2" data-fav-use="\${id}">Colocar no Monitor</button>
          <button class="btn rc-btn-red" data-fav-pin="\${id}">Fixar no Top 3</button>
        </div>
      </div>
    \`).join("");

    document.querySelectorAll("[data-fav-remove]").forEach(b=>{
      b.onclick = async () => {
        await hapticLight();
        const id = String(b.getAttribute("data-fav-remove"));
        S.favs = S.favs.filter(x => String(x) !== id);
        refreshFavs();
      };
    });

    document.querySelectorAll("[data-fav-use]").forEach(b=>{
      b.onclick = async () => {
        await hapticLight();
        const id = String(b.getAttribute("data-fav-use"));
        const inputs = [$("fx1"),$("fx2"),$("fx3")].filter(Boolean);
        for (const inp of inputs){
          if (!inp.value.trim()){ inp.value = id; break; }
        }
        document.querySelector('.tabbtn[data-tab="monitor"]')?.click();
      };
    });

    document.querySelectorAll("[data-fav-pin]").forEach(b=>{
      b.onclick = async () => {
        await hapticLight();
        const id = String(b.getAttribute("data-fav-pin"));
        const arr = S.favs.filter(x => String(x) !== id);
        arr.unshift(id);
        S.favs = arr;
        refreshFavs();
      };
    });
  }

  async function applyFavsToMonitor(){
    const favs = S.favs.map(String).slice(0,3);
    if(!favs.length) return;
    $("fx1") && ($("fx1").value = favs[0] || "");
    $("fx2") && ($("fx2").value = favs[1] || "");
    $("fx3") && ($("fx3").value = favs[2] || "");
    document.querySelector('.tabbtn[data-tab="monitor"]')?.click();
  }

  // ===== Monitor =====
  async function saveMonitor(){
    const ids = [$("fx1")?.value, $("fx2")?.value, $("fx3")?.value]
      .map(x => (x||"").trim()).filter(Boolean).slice(0,3);

    const j = await api("/api/live/set-fixtures", {
      method:"POST",
      headers:{ "Content-Type":"application/json" },
      body: JSON.stringify({ fixture_ids: ids })
    });

    $("snap") && ($("snap").textContent = JSON.stringify(j, null, 2));
    await refreshLive();
  }

  async function loadMonitor(){
    // não existe endpoint de "get fixtures"; então só mostra snapshots
    await refreshLive();
  }

  // ===== Config =====
  function loadConfigUI(){
    $("cfg-refresh-min") && ($("cfg-refresh-min").value = String(S.refreshMin || 10));
    $("cfg-alert-min") && ($("cfg-alert-min").value = String(S.alertMin || 80));
    $("cfg-haptic") && ($("cfg-haptic").value = S.haptic);
    $("cfg-economy") && ($("cfg-economy").value = S.economy);
    $("cfg-status") && ($("cfg-status").textContent = `Auto refresh: ${S.refreshMin} min | Alerta: ${S.alertMin} | Haptic: ${S.haptic} | Economia: ${S.economy}`);
  }

  function saveConfigUI(){
    const rm = Number($("cfg-refresh-min")?.value || 10);
    const am = Number($("cfg-alert-min")?.value || 80);
    const hp = $("cfg-haptic")?.value || "on";
    const ec = $("cfg-economy")?.value || "on";
    S.refreshMin = Math.max(1, Math.min(60, rm));
    S.alertMin = Math.max(50, Math.min(95, am));
    S.haptic = hp;
    S.economy = ec;
    loadConfigUI();
    setupAutoRefresh();
    updateBadges();
  }

  function resetConfig(){
    localStorage.removeItem("refreshMin");
    localStorage.removeItem("alertMin");
    localStorage.removeItem("haptic");
    localStorage.removeItem("economy");
    loadConfigUI();
    setupAutoRefresh();
    updateBadges();
  }

  // ===== Badges =====
  function updateBadges(lastResult){
    const alertMin = S.alertMin || 80;
    let hot = false;

    if (lastResult && typeof lastResult === "object") {
      const c = Number(lastResult.confianca);
      if (Number.isFinite(c) && c >= alertMin) hot = true;
    } else {
      // fallback: tenta ler do #out
      const out = $("out");
      if (out) {
        try {
          const j = JSON.parse(out.textContent || "{}");
          const c = Number(j.confianca);
          if (Number.isFinite(c) && c >= alertMin) hot = true;
        } catch(e){}
      }
    }

    const b = document.getElementById("badge-live");
    if (b) b.classList.toggle("on", hot);
  }

  // ===== Auto refresh =====
  let timer = null;
  function setupAutoRefresh(){
    if (timer) clearInterval(timer);
    const mins = S.refreshMin || 10;
    timer = setInterval(() => {
      refreshLive();
    }, mins * 60 * 1000);
  }

  // ===== Wire UI =====
  function wire(){
    $("btn-refresh-live") && ($("btn-refresh-live").onclick = async () => { await hapticLight(); await refreshLive(); });
    $("btn-analyze-all") && ($("btn-analyze-all").onclick = async () => { await hapticLight(); await analyzeAll(); });

    $("btn-refresh-rank") && ($("btn-refresh-rank").onclick = async () => { await hapticLight(); await refreshRank(); });
    $("btn-rank-now") && ($("btn-rank-now").onclick = async () => { await hapticLight(); await refreshRank(); });

    $("btn-fav-reload") && ($("btn-fav-reload").onclick = async () => { await hapticLight(); refreshFavs(); });
    $("btn-fav-apply-monitor") && ($("btn-fav-apply-monitor").onclick = async () => { await hapticLight(); await applyFavsToMonitor(); });

    $("btn-load-monitor") && ($("btn-load-monitor").onclick = async () => { await hapticLight(); await loadMonitor(); });
    $("btn-save-monitor") && ($("btn-save-monitor").onclick = async () => { await hapticLight(); await saveMonitor(); });

    $("btn-cfg-save") && ($("btn-cfg-save").onclick = async () => { await hapticLight(); saveConfigUI(); });
    $("btn-cfg-reset") && ($("btn-cfg-reset").onclick = async () => { await hapticLight(); resetConfig(); });
  }

  function boot(){
    loadConfigUI();
    refreshFavs();
    wire();
    setupAutoRefresh();
    refreshLive();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
</script>
</body>`);
}

fs.writeFileSync(p, html);
console.log("✅ 5 telas preenchidas + lógica conectada (/api/live + /api/analyze)");
NODE
