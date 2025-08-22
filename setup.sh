#!/usr/bin/env bash
set -euo pipefail

title() { echo -e "\n=== $* ==="; }
warn()  { echo -e "⚠️  $*"; }
info()  { echo -e "➡️  $*"; }
ok()    { echo -e "✅ $*"; }

"=== Kommunal-GPT Setup (Linux) ==="

# 1) Name abfragen
DEFAULT_NAME="Kommunal-GPT"
read -rp "Wie soll dein GPT heißen? [${DEFAULT_NAME}]: " COMPAINION_NAME
COMPAINION_NAME="${COMPAINION_NAME:-$DEFAULT_NAME}"
ok "Name gesetzt: ${COMPAINION_NAME}"

# 2) .env erstellen/aktualisieren
title "Konfiguriere .env"
if [[ ! -f ".env" && -f ".env.example" ]]; then
  cp .env.example .env
fi
touch .env
# COMPAINION_NAME setzen/ersetzen
if grep -q "^COMPAINION_NAME=" .env; then
  sed -i.bak "s|^COMPAINION_NAME=.*|COMPAINION_NAME='${COMPAINION_NAME}'|g" .env
else
  echo "COMPAINION_NAME='${COMPAINION_NAME}'" >> .env
fi
# OLLAMA_BASE_URL setzen/ersetzen
if grep -q "^OLLAMA_BASE_URL=" .env; then
  sed -i.bak "s|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL='http://localhost:11434'|g" .env
else
  echo "OLLAMA_BASE_URL='http://localhost:11434'" >> .env
fi
rm -f .env.bak
ok ".env aktualisiert"

# 3) Docker installieren/prüfen
title "Prüfe/Installiere Docker"
OS="$(uname -s)"
if ! command -v docker >/dev/null 2>&1; then
  if [[ "$OS" == "Darwin" ]]; then
    info "macOS erkannt. Installiere Homebrew/Colima + Docker CLI (CLI-only)."
    if ! command -v brew >/dev/null 2>&1; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install docker colima
    colima start || true
  elif [[ "$OS" == "Linux" ]]; then
    info "Linux erkannt. Installiere Docker Engine (benötigt sudo)."
    curl -fsSL https://get.docker.com | sh
    if command -v systemctl >/dev/null 2>&1; then
      sudo systemctl enable docker || true
      sudo systemctl start docker || true
    fi
    if command -v usermod >/dev/null 2>&1; then
      sudo usermod -aG docker "$USER" || true
      warn "Du musst dich ggf. neu anmelden, damit Gruppenrechte greifen."
    fi
  else
    warn "Nicht unterstütztes OS: $OS. Bitte Docker manuell installieren."
  fi
else
  ok "Docker vorhanden: $(docker --version)"
fi

# 4) Docker Compose Pull
title "Pull Docker-Images"
docker compose pull

# 5) Initialstart nur OWUI (Ressourcen anlegen)
title "Initialer Start (Ressourcen anlegen)"
docker compose up -d kommunal-gpt-frontend
sleep 20
docker compose down

# 6) DB/Statics kopieren
title "Standard-Datenbank einsetzen"
if [[ -f "master-webui.db" ]]; then
  sudo cp -f master-webui.db owui/data/webui.db
  ok "DB eingesetzt: owui/data/webui.db"
else
  warn "master-webui.db nicht gefunden – übersprungen."
fi

if compgen -G "static/*.*" >/dev/null; then
  sudo cp -f static/*.* owui/static/ || true
  ok "Konfiguration eingespielt"
else
  warn "Keine Konfiguration gefunden – übersprungen."
fi

# 7) Gesamtsystem starten
title "Starte System"
docker compose up -d

# 8) Optional: Modelle laden
warn "Die Modelle werden jetzt geladen, dies kann je nach Geschwindigkeit Ihrer Internetverbindung eine Weile dauern!"
if [[ -x "./models.sh" ]]; then
  chmod +x models.sh
  ./models.sh
else
  warn "models.sh nicht ausführbar oder nicht vorhanden."
fi

ok "Setup abgeschlossen."
info "Bitte loggen Sie sich im Browser unter http://localhost:3000 ein."
info "E-Mail: admin@deepmentation.ai"
info "Passwort: CompAdmin#2025!"