import express from "express";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";

dotenv.config();

const app = express();
app.use(express.json({ limit: "512kb" }));
app.use(express.static("public"));

const PORT = process.env.PORT || 3000;
const HISTORY_FILE = path.resolve("./history.json");

function safeNum(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}
function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}
function nowISO() {
  return new Date().toISOString();
}

// ===== History =====
function readHistory() {
  try {
    if (!fs.existsSync(HISTORY_FILE)) return [];
    const raw = fs.readFileSync(HISTORY_FILE, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
function writeHistory(items) {
  fs.writeFileSync(HISTORY_FILE, JSON.stringify(items, null, 2));
}

// ===== Heurística (fallback + ranking local) =====
function computeHeuristic(data) {
  const minute = clamp(safeNum(data.minute, 0), 0, 120);
  const corners = clamp(safeNum(data.corners_total, 0), 0, 50);
  const shots = clamp(safeNum(data.shots_total, 0), 0, 80);
  const sot = clamp(safeNum(data.shots_on_target, 0), 0, 30);
  const reds = clamp(safeNum(data.red_cards, 0), 0, 4);

  const paceCorners = minute > 0 ? corners / minute : 0;
  const paceShots = minute > 0 ? shots / minute : 0;

  let score = 0;
  score += clamp(paceCorners * 160, 0, 55);
  score += clamp(paceShots * 80, 0, 25);
  score += clamp(sot * 3, 0, 15);

  // bônus leve se alguém “parece” pressionar
  if (data.pressure_side === "Mandante" || data.pressure_side === "Visitante") score += 5;

  // vermelho derruba confiança
  if (reds > 0) score -= 18;

  score = clamp(Math.round(score), 0, 100);

  const proj = paceCorners * 95;
  let linha = "Over 6.5";
  if (proj >= 10.5) linha = "Over 9.5";
  else if (proj >= 9.5) linha = "Over 8.5";
  else if (proj >= 8.5) linha = "Over 7.5";

  let acao = "ESPERAR";
  if (score >= 70) acao = "ENTRAR";
  else if (score < 45) acao = "PULAR";

  return {
    acao,
    confianca: score,
    linha_sugerida: linha,
    justificativa_curta:
      reds > 0
        ? "Cartão vermelho aumenta imprevisibilidade. Só entrar se o ritmo estiver MUITO acima da média."
        : "Decisão baseada no ritmo (escanteios/min), pressão e volume de finalizações.",
    checklist: [
      "3+ escanteios até 25’ (bom sinal)",
      "Cruzamentos/chutes bloqueados",
      "Time perdendo tende a forçar escanteios",
      "Evitar jogo truncado/sem ataques",
      "Cuidado com cartão vermelho"
    ],
    cashout_plano:
      "Se atingir ~70% da linha até 60–65’ e o ritmo cair, considerar cashout parcial/total para proteger lucro.",
    gestao_banca:
      "Use entrada fracionada. Preserve parte do lucro fora da próxima aposta (ex: 30–50%)."
  };
}

// ===== API-Football =====
const AF_KEY = process.env.API_FOOTBALL_KEY || "";
const AF_HOST = "v3.football.api-sports.io";
const REFRESH_SECONDS = clamp(safeNum(process.env.LIVE_REFRESH_SECONDS, 600), 60, 3600);

let liveFixtureIds = [];
let liveCache = {}; // fixtureId -> { ok, updated_at, data, error }

let liveListCache = { updated_at: 0, ok: false, data: [], error: "" };
const LIVE_LIST_TTL_MS = 60_000;

// cache de avaliação por clique (pra não gastar repetido)
let evalCache = {}; // fixtureId -> { at_ms, ok, data, error }
const EVAL_TTL_MS = 120_000; // 2 min

async function afFetchJson(pathname) {
  if (!AF_KEY || AF_KEY.includes("COLE_SUA_CHAVE")) throw new Error("API_FOOTBALL_KEY não configurada");
  const url = `https://${AF_HOST}${pathname}`;
  const r = await fetch(url, { headers: { "x-apisports-key": AF_KEY } });
  const txt = await r.text();
  if (!r.ok) throw new Error(`API-Football HTTP ${r.status}: ${txt.slice(0, 300)}`);
  return JSON.parse(txt);
}

function statValue(statsArr, typeName) {
  const found = (statsArr || []).find(x => (x?.type || "").toLowerCase() === typeName.toLowerCase());
  const v = found?.value;
  if (v == null) return null;
  if (typeof v === "number") return v;
  const n = Number(String(v).replace(/[^\d\-]/g, ""));
  return Number.isFinite(n) ? n : null;
}

async function getLiveSnapshot(fixtureId) {
  const fx = await afFetchJson(`/fixtures?id=${encodeURIComponent(fixtureId)}`);
  const item = fx?.response?.[0];
  if (!item) throw new Error("Fixture não encontrado");

  const minute = item?.fixture?.status?.elapsed ?? 0;
  const scoreHome = item?.goals?.home ?? 0;
  const scoreAway = item?.goals?.away ?? 0;

  const st = await afFetchJson(`/fixtures/statistics?fixture=${encodeURIComponent(fixtureId)}`);
  const teams = st?.response || [];
  const homeStats = teams?.[0]?.statistics || [];
  const awayStats = teams?.[1]?.statistics || [];

  const cornersHome = statValue(homeStats, "Corner Kicks") ?? 0;
  const cornersAway = statValue(awayStats, "Corner Kicks") ?? 0;

  const shotsHome = statValue(homeStats, "Total Shots") ?? 0;
  const shotsAway = statValue(awayStats, "Total Shots") ?? 0;

  const sotHome = statValue(homeStats, "Shots on Goal") ?? 0;
  const sotAway = statValue(awayStats, "Shots on Goal") ?? 0;

  const corners_total = cornersHome + cornersAway;
  const shots_total = shotsHome + shotsAway;
  const shots_on_target = sotHome + sotAway;

  const homeName = item?.teams?.home?.name || "Home";
  const awayName = item?.teams?.away?.name || "Away";

  let pressure_side = "Equilibrado";
  if (shotsHome > shotsAway + 2) pressure_side = "Mandante";
  else if (shotsAway > shotsHome + 2) pressure_side = "Visitante";

  // economia: não buscar eventos
  const red_cards = 0;

  return {
    fixture_id: String(fixtureId),
    match: `${homeName} vs ${awayName}`,
    minute,
    score: `${scoreHome}-${scoreAway}`,
    corners_home: cornersHome,
    corners_away: cornersAway,
    corners_total,
    shots_total,
    shots_on_target,
    pressure_side,
    red_cards,
    updated_at: nowISO()
  };
}

// modo econômico: só atualiza automático se estiver em janela útil
function ecoShouldRefresh(snapshot) {
  const m = snapshot?.minute ?? 0;
  if (m < 12) return false;
  if (m > 85) return false;
  return true;
}

async function refreshLiveCacheOnce({ force = false } = {}) {
  const ids = liveFixtureIds.slice(0, 3);
  if (!ids.length) return;

  for (const id of ids) {
    try {
      const prev = liveCache[String(id)]?.data;
      if (!force && prev && !ecoShouldRefresh(prev)) continue;

      const snap = await getLiveSnapshot(id);
      liveCache[String(id)] = { ok: true, updated_at: nowISO(), data: snap };
    } catch (e) {
      liveCache[String(id)] = { ok: false, updated_at: nowISO(), error: String(e) };
    }
  }
}

// auto refresh
setInterval(() => {
  refreshLiveCacheOnce({ force: false }).catch(() => {});
}, REFRESH_SECONDS * 1000);

// ===== Endpoints =====
app.get("/api/history", (_req, res) => res.json({ items: readHistory() }));

app.post("/api/history", (req, res) => {
  const entry = req.body;
  if (!entry || typeof entry !== "object") return res.status(400).json({ error: "invalid body" });
  const items = readHistory();
  items.unshift(entry);
  writeHistory(items.slice(0, 500));
  res.json({ ok: true });
});

app.patch("/api/history/:id", (req, res) => {
  const { id } = req.params;
  const patch = req.body || {};
  const items = readHistory();
  const idx = items.findIndex(x => x && x.id === id);
  if (idx === -1) return res.status(404).json({ error: "not found" });
  items[idx] = { ...items[idx], ...patch, updated_at: nowISO() };
  writeHistory(items);
  res.json({ ok: true });
});

// Lista jogos ao vivo (cache 60s)
app.get("/api/live/list", async (_req, res) => {
  const now = Date.now();
  if (liveListCache.ok && (now - liveListCache.updated_at) < LIVE_LIST_TTL_MS) {
    return res.json({ ok: true, cached: true, items: liveListCache.data, updated_at: new Date(liveListCache.updated_at).toISOString() });
  }
  try {
    const j = await afFetchJson(`/fixtures?live=all`);
    const items = (j.response || []).map(x => ({
      fixture_id: String(x.fixture.id),
      league: x.league?.name || "",
      country: x.league?.country || "",
      minute: x.fixture?.status?.elapsed ?? 0,
      status: x.fixture?.status?.short || "",
      home: x.teams?.home?.name || "",
      away: x.teams?.away?.name || "",
      score: `${x.goals?.home ?? 0}-${x.goals?.away ?? 0}`,
    }));
    liveListCache = { ok: true, updated_at: now, data: items, error: "" };
    res.json({ ok: true, cached: false, items, updated_at: nowISO() });
  } catch (e) {
    liveListCache = { ok: false, updated_at: now, data: [], error: String(e) };
    res.json({ ok: false, error: String(e) });
  }
});

// Selecionar fixtures para monitorar
app.post("/api/live/set-fixtures", async (req, res) => {
  const ids = Array.isArray(req.body?.fixture_ids) ? req.body.fixture_ids : [];
  liveFixtureIds = ids.map(String).slice(0, 3);
  await refreshLiveCacheOnce({ force: true }).catch(() => {});
  res.json({ ok: true, fixture_ids: liveFixtureIds, refresh_seconds: REFRESH_SECONDS });
});

app.get("/api/live/snapshots", (_req, res) => {
  const ids = liveFixtureIds.slice(0, 3);
  const items = ids.map(id => liveCache[String(id)] || { ok: false, error: "Sem dados ainda" });
  res.json({ fixture_ids: ids, refresh_seconds: REFRESH_SECONDS, items });
});

app.post("/api/live/force-refresh", async (_req, res) => {
  await refreshLiveCacheOnce({ force: true }).catch(() => {});
  res.json({ ok: true, at: nowISO() });
});

// ✅ Avaliar UM jogo (por clique) com cache 2 min
app.get("/api/live/eval/:fixtureId", async (req, res) => {
  const fixtureId = String(req.params.fixtureId || "").trim();
  if (!fixtureId) return res.status(400).json({ ok: false, error: "fixtureId required" });

  const now = Date.now();
  const cached = evalCache[fixtureId];
  if (cached && (now - cached.at_ms) < EVAL_TTL_MS) {
    return res.json({ ok: true, cached: true, ...cached.data });
  }

  try {
    const snap = await getLiveSnapshot(fixtureId);
    const heur = computeHeuristic(snap);
    const payload = { snapshot: snap, heuristic: heur };

    evalCache[fixtureId] = { at_ms: now, ok: true, data: payload, error: "" };
    res.json({ ok: true, cached: false, ...payload });
  } catch (e) {
    evalCache[fixtureId] = { at_ms: now, ok: false, data: null, error: String(e) };
    res.json({ ok: false, error: String(e) });
  }
});

// Análise (OpenAI opcional; fallback heurística)
app.post("/api/analyze", async (req, res) => {
  try {
    const data = req.body || {};
    const apiKey = process.env.OPENAI_API_KEY || "";
    const local = computeHeuristic(data);

    if (!apiKey || apiKey.includes("COLE_SUA_CHAVE")) {
      return res.json({ mode: "heuristic_only", result: local });
    }

    const system = `
Você é um analista focado em ESCANTEIOS ao vivo.
Objetivo: reduzir decisões emocionais e sugerir entradas com base em sinais estatísticos.
NÃO prometa lucro, NÃO garanta ganhos. Seja direto.
Responda em PT-BR e retorne APENAS JSON estrito com:
{
  "acao": "ENTRAR" | "ESPERAR" | "PULAR",
  "confianca": number (0-100),
  "linha_sugerida": string,
  "justificativa_curta": string,
  "checklist": string[],
  "cashout_plano": string,
  "gestao_banca": string
}`.trim();

    const user = `
Dados do jogo (ao vivo):
- Minuto: ${data.minute}
- Placar: ${data.score}
- Escanteios total: ${data.corners_total}
- Escanteios mandante/visitante: ${data.corners_home}/${data.corners_away}
- Finalizações totais: ${data.shots_total}
- Finalizações no alvo: ${data.shots_on_target}
- Quem pressiona: ${data.pressure_side}
- Cartões vermelhos: ${data.red_cards}
Observações: ${data.notes ?? ""}
`.trim();

    const r = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: "gpt-5.2",
        input: [{ role: "system", content: system }, { role: "user", content: user }],
        text: { format: { type: "text" } }
      })
    });

    const raw = await r.text();
    if (!r.ok) return res.json({ mode: "heuristic_fallback", result: local, api_error: raw.slice(0, 800) });

    const out = JSON.parse(raw);
    const outputText = out.output_text || "";
    try {
      const parsed = JSON.parse(outputText);
      res.json({ mode: "ai", result: parsed });
    } catch {
      res.json({ mode: "ai_unparsed", raw: outputText || "(sem texto)", heuristic: local });
    }
  } catch (e) {
    res.status(500).json({ error: "Server error", details: String(e) });
  }
});

app.get("/health", (_req, res) => res.json({ ok: true }));

app.listen(PORT, () => {
  console.log(`✅ Rodando em http://127.0.0.1:${PORT}`);
  console.log(`✅ Auto-refresh: ${REFRESH_SECONDS}s | Eval TTL: ${EVAL_TTL_MS/1000}s`);
});
