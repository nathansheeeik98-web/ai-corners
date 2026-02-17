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
  // escrita simples (OK pra uso local)
  fs.writeFileSync(HISTORY_FILE, JSON.stringify(items, null, 2));
}

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

  if (data.pressure_side === "Mandante" || data.pressure_side === "Visitante") score += 5;
  if (reds > 0) score -= 18;

  score = clamp(Math.round(score), 0, 100);

  // projeção
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

function adjustByMode(base, mode) {
  // Ajustes de modo (sem prometer nada; apenas mais/menos seletivo)
  const out = { ...base };
  const c = safeNum(out.confianca, 50);

  if (mode === "CONSERVADOR") {
    // mais seletivo
    if (c < 75) out.acao = "ESPERAR";
    if (c < 55) out.acao = "PULAR";
    // linhas mais baixas
    if (out.linha_sugerida === "Over 9.5") out.linha_sugerida = "Over 8.5";
    if (out.linha_sugerida === "Over 8.5") out.linha_sugerida = "Over 7.5";
  }

  if (mode === "AGRESSIVO") {
    // menos seletivo
    if (c >= 62) out.acao = "ENTRAR";
    // pode aceitar uma linha um pouco maior se o score for alto
    if (c >= 82 && out.linha_sugerida === "Over 7.5") out.linha_sugerida = "Over 8.5";
  }

  // AUTO = não muda diretamente; quem decide é a regra de objetivo no front (mas mantemos aqui neutro)
  return out;
}

// --- Histórico API ---
app.get("/api/history", (_req, res) => {
  res.json({ items: readHistory() });
});

app.post("/api/history", (req, res) => {
  const entry = req.body;
  if (!entry || typeof entry !== "object") return res.status(400).json({ error: "invalid body" });

  const items = readHistory();
  items.unshift(entry);
  // limita pra não crescer infinito
  const limited = items.slice(0, 500);
  writeHistory(limited);

  res.json({ ok: true, count: limited.length });
});

app.patch("/api/history/:id", (req, res) => {
  const { id } = req.params;
  const patch = req.body || {};
  const items = readHistory();
  const idx = items.findIndex(x => x && x.id === id);
  if (idx === -1) return res.status(404).json({ error: "not found" });

  items[idx] = { ...items[idx], ...patch, updated_at: new Date().toISOString() };
  writeHistory(items);
  res.json({ ok: true });
});

// --- Análise ---
app.post("/api/analyze", async (req, res) => {
  try {
    const data = req.body || {};
    const apiKey = process.env.OPENAI_API_KEY;
    const mode = (data.mode || "AUTO").toUpperCase();

    // fallback local
    const localBase = computeHeuristic(data);
    const local = adjustByMode(localBase, mode);

    if (!apiKey || apiKey.includes("COLE_SUA_CHAVE_AQUI")) {
      return res.json({
        mode: "heuristic_only",
        result: local,
        note: "Configure OPENAI_API_KEY no .env para ativar IA."
      });
    }

    const system = `
Você é um analista focado em ESCANTEIOS ao vivo.
Objetivo: reduzir decisões emocionais e sugerir entradas com base em sinais estatísticos.
NÃO prometa lucro, NÃO garanta ganhos. Seja direto e disciplinado.
Responda em PT-BR e retorne APENAS JSON estrito com:
{
  "acao": "ENTRAR" | "ESPERAR" | "PULAR",
  "confianca": number (0-100),
  "linha_sugerida": string,
  "justificativa_curta": string,
  "checklist": string[],
  "cashout_plano": string,
  "gestao_banca": string
}
Regras:
- Se houver cartão vermelho, prefira "PULAR" ou "ESPERAR", salvo ritmo MUITO forte.
- Se o modo for CONSERVADOR: sugira linhas mais baixas (Over 6.5/7.5/8.5) e seja mais seletivo.
- Se o modo for AGRESSIVO: pode aceitar um pouco mais de risco, mas sem exagero.
`.trim();

    const user = `
Modo: ${mode}
Dados do jogo (ao vivo):
- Minuto: ${data.minute}
- Placar: ${data.score}
- Escanteios total: ${data.corners_total}
- Escanteios mandante/visitante: ${data.corners_home}/${data.corners_away}
- Finalizações totais: ${data.shots_total}
- Finalizações no alvo: ${data.shots_on_target}
- Ataques perigosos: ${data.dangerous_attacks ?? "N/A"}
- Quem pressiona: ${data.pressure_side}
- Cartões vermelhos: ${data.red_cards}
- Observações: ${data.notes ?? ""}
Contexto: usuário quer consistência em escanteios ao vivo, com disciplina e gestão de banca.
`.trim();

    const r = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model: "gpt-5.2",
        input: [
          { role: "system", content: system },
          { role: "user", content: user }
        ],
        text: { format: { type: "text" } }
      })
    });

    if (!r.ok) {
      const details = await r.text();
      return res.status(200).json({
        mode: "heuristic_fallback",
        result: local,
        note: "Falha na IA, usando heurística local.",
        api_error: details.slice(0, 1000)
      });
    }

    const out = await r.json();

    let outputText = "";
    if (out.output && Array.isArray(out.output)) {
      for (const o of out.output) {
        if (o.content && Array.isArray(o.content)) {
          for (const c of o.content) {
            if (typeof c.text === "string") outputText += c.text;
            if (c.text && typeof c.text.value === "string") outputText += c.text.value;
          }
        }
      }
    }
    if (!outputText && typeof out.output_text === "string") outputText = out.output_text;

    try {
      const parsed = JSON.parse(outputText);
      const adjusted = adjustByMode(parsed, mode);
      return res.json({ mode: "ai", result: adjusted });
    } catch {
      return res.json({ mode: "ai_unparsed", raw: outputText || "(sem texto)", heuristic: local });
    }
  } catch (e) {
    return res.status(500).json({ error: "Server error", details: String(e) });
  }
});

app.get("/health", (_req, res) => res.json({ ok: true }));

app.listen(PORT, () => {
  console.log("✅ Rodando em http://127.0.0.1:" + PORT);
});
