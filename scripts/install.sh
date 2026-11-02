#!/bin/zsh
# Baut NotchIsland (Release), kopiert die App nach /Applications und startet sie.
# Beim ersten Start aus /Applications registriert sich die App selbst als Anmeldeobjekt.
set -euo pipefail

cd "$(dirname "$0")/.."

# Falls xcode-select auf die Command Line Tools zeigt, Xcode direkt verwenden.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "→ Baue NotchIsland (Release) …"
xcodebuild \
  -project NotchIsland.xcodeproj \
  -scheme NotchIsland \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build | grep -E "error:|BUILD" || true

APP="build/DerivedData/Build/Products/Release/NotchIsland.app"
if [[ ! -d "$APP" ]]; then
  echo "Build fehlgeschlagen – $APP nicht gefunden." >&2
  exit 1
fi

TARGET="/Applications/NotchIsland.app"
echo "→ Beende laufende Instanz …"
pkill -x NotchIsland 2>/dev/null || true
sleep 1

echo "→ Installiere nach $TARGET …"
if [[ -d "$TARGET" ]]; then
  rm -r "$TARGET"
fi
ditto "$APP" "$TARGET"

echo "→ Starte NotchIsland …"
open "$TARGET"
echo "Fertig. Das Menüleisten-Icon öffnet die Einstellungen."
