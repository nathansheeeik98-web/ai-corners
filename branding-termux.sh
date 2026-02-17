#!/data/data/com.termux/files/usr/bin/bash
set -e

APP_NAME="${1:-Escanteios da Felicidade}"

echo "✅ Aplicando branding (Termux safe)..."
echo "Nome: $APP_NAME"
echo ""

# 1) garantir typescript (cap config ts)
npm i -D typescript >/dev/null 2>&1 || npm i -D typescript

# 2) atualizar capacitor.config.ts (se existir)
if [ -f capacitor.config.ts ]; then
  # tenta trocar appName em TS
  sed -i "s/appName: *\"[^\"]*\"/appName: \"${APP_NAME//\"/\\\"}\"/g" capacitor.config.ts || true
  sed -i "s/appName: *'[^']*'/appName: '${APP_NAME//\'/\\\'}'/g" capacitor.config.ts || true
fi

# 3) sync para garantir pasta android
npx cap sync android

# 4) trocar nome no Android strings.xml
STR1="android/app/src/main/res/values/strings.xml"
if [ -f "$STR1" ]; then
  # troca o app_name
  if grep -q 'name="app_name"' "$STR1"; then
    sed -i "s#<string name=\"app_name\">.*</string>#<string name=\"app_name\">${APP_NAME}</string>#g" "$STR1"
  else
    # se não existir, adiciona
    sed -i "s#</resources>#  <string name=\"app_name\">${APP_NAME}</string>\n</resources>#g" "$STR1"
  fi
fi

# 5) tema vermelho/preto (cores)
COL="android/app/src/main/res/values/colors.xml"
mkdir -p android/app/src/main/res/values
if [ ! -f "$COL" ]; then
cat > "$COL" <<COLORS
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="colorPrimary">#E10600</color>
  <color name="colorPrimaryDark">#8B0000</color>
  <color name="colorAccent">#E10600</color>
  <color name="colorBackground">#0F0F0F</color>
</resources>
COLORS
else
  # atualiza se já existir
  perl -0777 -i -pe 's#<color name="colorPrimary">.*?</color>#<color name="colorPrimary">#E10600</color>#g' "$COL" || true
  perl -0777 -i -pe 's#<color name="colorPrimaryDark">.*?</color>#<color name="colorPrimaryDark">#8B0000</color>#g' "$COL" || true
  perl -0777 -i -pe 's#<color name="colorAccent">.*?</color>#<color name="colorAccent">#E10600</color>#g' "$COL" || true
fi

echo ""
echo "✅ Pronto no Termux!"
echo "👉 Nome atualizado + tema vermelho/preto."
echo ""
echo "Agora: commit + push e rode o workflow do APK no GitHub."
