#!/data/data/com.termux/files/usr/bin/bash
set -e

WF=".github/workflows/android-apk.yml"
mkdir -p .github/workflows

if [ ! -f "$WF" ]; then
  echo "❌ Não achei $WF"
  exit 1
fi

# Insere steps de gerar ícone/splash + capacitor-assets antes do build do Android
# (mantém o restante do workflow)
python - <<'PY'
import re, pathlib
p = pathlib.Path(".github/workflows/android-apk.yml")
y = p.read_text(encoding="utf-8")

# garante Node 22 e Java 21 já existentes; só adiciona os steps depois do npm install
marker = r"- name: Install deps\s*\n\s*run: npm install\s*\n"
m = re.search(marker, y)
if not m:
    print("❌ Não encontrei o step 'Install deps'. Aborta.")
    raise SystemExit(1)

inject = """- name: Install deps
        run: npm install

      - name: Install asset tools (CI only)
        run: npm i -D typescript @capacitor/assets sharp

      - name: Create RedCorner icon (SVG)
        run: |
          mkdir -p assets
          cat > assets/icon.svg <<'SVG'
          <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
            <defs>
              <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0" stop-color="#E10600"/>
                <stop offset="1" stop-color="#8B0000"/>
              </linearGradient>
              <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
                <feDropShadow dx="0" dy="18" stdDeviation="18" flood-color="#000" flood-opacity="0.55"/>
              </filter>
            </defs>
            <rect width="1024" height="1024" rx="220" fill="#0F0F0F"/>
            <circle cx="512" cy="512" r="310" fill="url(#g)" filter="url(#shadow)"/>
            <path d="M355 690 V390 C355 360 379 336 409 336 H680"
                  fill="none" stroke="#FFF" stroke-width="44" stroke-linecap="round" stroke-linejoin="round" opacity="0.95"/>
            <path d="M355 392 L520 330 L520 455 L355 515 Z" fill="#FFF" opacity="0.95"/>
            <path d="M440 620 L520 545 L585 600 L705 480"
                  fill="none" stroke="#FFF" stroke-width="38" stroke-linecap="round" stroke-linejoin="round" opacity="0.95"/>
            <path d="M705 480 L705 560" fill="none" stroke="#FFF" stroke-width="38" stroke-linecap="round" opacity="0.95"/>
            <path d="M705 480 L625 480" fill="none" stroke="#FFF" stroke-width="38" stroke-linecap="round" opacity="0.95"/>
          </svg>
          SVG

      - name: Generate icon.png + splash.png (sharp)
        run: node - <<'NODE'
          const fs = require("fs");
          const sharp = require("sharp");

          (async () => {
            const svg = fs.readFileSync("assets/icon.svg");
            await sharp(svg).png().resize(1024,1024).toFile("assets/icon.png");

            const bg = { r: 0x0F, g: 0x0F, b: 0x0F, alpha: 1 };
            const icon = await sharp(svg).png().resize(720,720).toBuffer();

            await sharp({ create: { width: 2732, height: 2732, channels: 4, background: bg } })
              .composite([{ input: icon, gravity: "center" }])
              .png()
              .toFile("assets/splash.png");
            console.log("OK assets generated");
          })().catch(e => { console.error(e); process.exit(1); });
          NODE

      - name: Generate Capacitor assets
        run: npx capacitor-assets generate
"""

y2 = re.sub(marker, inject, y, count=1)
p.write_text(y2, encoding="utf-8")
print("✅ Workflow atualizado com geração automática de ícone/splash no CI.")
PY

echo "✅ Patch aplicado. Agora faça commit e push."
