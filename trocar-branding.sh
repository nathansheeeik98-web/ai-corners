#!/data/data/com.termux/files/usr/bin/bash
set -e

APP_NAME="${1:-Escanteios da Felicidade}"
PRIMARY_RED="#E10600"
BG_BLACK="#0F0F0F"

echo "✅ Aplicando branding..."
echo "App Name: $APP_NAME"
echo "Cores: vermelho $PRIMARY_RED | preto $BG_BLACK"
echo ""

# 1) Dependências para gerar PNG a partir de SVG e gerar assets do Capacitor
npm i -D @capacitor/assets sharp >/dev/null 2>&1 || npm i -D @capacitor/assets sharp

# 2) Pasta assets
mkdir -p assets

# 3) ÍCONE (SVG) - estilo moderno: círculo vermelho + canto + setinha (minimal)
cat > assets/icon.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${PRIMARY_RED}"/>
      <stop offset="1" stop-color="#8B0000"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="18" stdDeviation="18" flood-color="#000000" flood-opacity="0.55"/>
    </filter>
  </defs>

  <!-- fundo -->
  <rect width="1024" height="1024" rx="220" fill="${BG_BLACK}"/>

  <!-- círculo vermelho central -->
  <circle cx="512" cy="512" r="310" fill="url(#g)" filter="url(#shadow)"/>

  <!-- “canto” estilizado (escanteio) -->
  <path d="M355 690 V390 C355 360 379 336 409 336 H680"
        fill="none" stroke="#FFFFFF" stroke-width="44" stroke-linecap="round" stroke-linejoin="round" opacity="0.95"/>

  <!-- bandeirinha -->
  <path d="M355 392 L520 330 L520 455 L355 515 Z"
        fill="#FFFFFF" opacity="0.95"/>

  <!-- setinha/grafico subindo (IA / tendência) -->
  <path d="M440 620 L520 545 L585 600 L705 480"
        fill="none" stroke="#FFFFFF" stroke-width="38" stroke-linecap="round" stroke-linejoin="round" opacity="0.95"/>
  <path d="M705 480 L705 560"
        fill="none" stroke="#FFFFFF" stroke-width="38" stroke-linecap="round" opacity="0.95"/>
  <path d="M705 480 L625 480"
        fill="none" stroke="#FFFFFF" stroke-width="38" stroke-linecap="round" opacity="0.95"/>
</svg>
SVG

# 4) Gerar PNGs (icon + splash) via sharp
node - <<'NODE'
const fs = require("fs");
const sharp = require("sharp");

(async () => {
  const iconSvg = fs.readFileSync("assets/icon.svg");

  // icon 1024
  await sharp(iconSvg).png().resize(1024,1024).toFile("assets/icon.png");

  // splash: fundo preto com ícone menor central
  const bg = { r: 0x0F, g: 0x0F, b: 0x0F, alpha: 1 };
  const icon = await sharp(iconSvg).png().resize(720,720).toBuffer();

  // 2732x2732 (bom pra splash)
  await sharp({
    create: { width: 2732, height: 2732, channels: 4, background: bg }
  })
    .composite([{ input: icon, gravity: "center" }])
    .png()
    .toFile("assets/splash.png");

  console.log("✅ assets/icon.png e assets/splash.png gerados");
})().catch(e => { console.error(e); process.exit(1); });
NODE

# 5) Trocar nome do app no capacitor.config.ts / .json
if [ -f capacitor.config.ts ]; then
  # tenta trocar appName: "..."
  if grep -q "appName" capacitor.config.ts; then
    sed -i "s/appName: *\"[^\"]*\"/appName: \"${APP_NAME//\"/\\\"}\"/g" capacitor.config.ts
    sed -i "s/appName: *'[^']*'/appName: '${APP_NAME//\'/\\\'}'/g" capacitor.config.ts
  fi
elif [ -f capacitor.config.json ]; then
  node - <<NODE
const fs = require("fs");
const p = "capacitor.config.json";
const j = JSON.parse(fs.readFileSync(p,"utf8"));
j.appName = ${JSON.stringify(APP_NAME)};
fs.writeFileSync(p, JSON.stringify(j,null,2));
console.log("✅ capacitor.config.json atualizado");
NODE
fi

# 6) Gerar ícones/splash para Android (e iOS se existir)
# O @capacitor/assets usa assets/icon.png e assets/splash.png por padrão
npx capacitor-assets generate

# 7) Sync Android
npx cap sync android

echo ""
echo "✅ Branding aplicado com sucesso!"
echo "👉 Nome: $APP_NAME"
echo "👉 Ícone e Splash: vermelho/preto"
echo ""
echo "Agora só rodar seu workflow do APK no GitHub Actions de novo."
