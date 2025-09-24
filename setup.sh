#!/usr/bin/env bash
set -euo pipefail

title() { echo -e "\n=== $* ==="; }
warn()  { echo -e "⚠️  $*"; }
info()  { echo -e "➡️  $*"; }
ok()    { echo -e "✅ $*"; }

echo "=== KommunalGPT Setup (Linux) ==="

# 1) Name abfragen
DEFAULT_NAME="KommunalGPT"
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
  warn "Docker wurde noch nicht auf dem System gefunden."
  echo "Möchten Sie eine automatische Installation durch dieses Setup durchführen lassen"
  echo "oder Docker selbst installieren und anschließend dieses Setup erneut starten?"
  echo ""
  echo "1) Automatische Installation durch Setup"
  echo "2) Docker selbst installieren und Setup später erneut starten"
  echo ""
  read -rp "Ihre Wahl [1/2]: " DOCKER_CHOICE
  
  case "$DOCKER_CHOICE" in
    1)
      if [[ "$OS" == "Linux" ]]; then
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
        warn "Nicht unterstütztes OS: $OS. Dieses Setup unterstützt nur Linux."
        exit 1
      fi
      ;;
    2)
      info "Bitte installieren Sie Docker manuell und starten Sie dieses Setup anschließend erneut."
      exit 0
      ;;
    *)
      warn "Ungültige Auswahl. Setup wird beendet."
      exit 1
      ;;
  esac
else
  ok "Docker wurde bereits auf dem System gefunden, Installation von Docker wird übersprungen."
  ok "Docker Version: $(docker --version)"
fi

# 4) Ollama installieren/prüfen
title "Prüfe/Installiere Ollama"

# Prüfe ob Ollama API bereits erreichbar ist
OLLAMA_RUNNING=false
if curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
  OLLAMA_RUNNING=true
  OLLAMA_VERSION=$(curl -s http://localhost:11434/api/version 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unbekannt")
  ok "Ollama API ist bereits erreichbar (Version: $OLLAMA_VERSION)"
  
  # Prüfe ob es ein Docker-Container ist
  if docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
    ok "Ollama läuft bereits als Docker-Container"
    OLLAMA_TYPE="docker"
  else
    ok "Ollama läuft lokal auf dem System"
    OLLAMA_TYPE="local"
  fi
elif command -v ollama >/dev/null 2>&1; then
  warn "Ollama ist installiert, aber API nicht erreichbar. Starte Ollama..."
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl start ollama || true
    sleep 5
  else
    ollama serve &
    sleep 5
  fi
  
  if curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
    OLLAMA_RUNNING=true
    OLLAMA_TYPE="local"
    ok "Ollama erfolgreich gestartet"
  else
    warn "Ollama konnte nicht gestartet werden. Verwende Docker-Container."
    OLLAMA_TYPE="docker"
  fi
else
  info "Ollama wurde noch nicht auf dem System gefunden."
  info "Das Setup wird Ollama als Docker-Container bereitstellen."
  OLLAMA_TYPE="docker"
fi

# Informiere über Modell-Installation
if [[ "$OLLAMA_RUNNING" == "true" ]]; then
  if [[ "$OLLAMA_TYPE" == "local" ]]; then
    ok "Hinweis: Das bereits lokal installierte Ollama wird verwendet."
    warn "Die Modelle werden in die lokale Ollama-Installation geladen."
    warn "Das models.sh Skript wird entsprechend angepasst ausgeführt."
  else
    ok "Hinweis: Das bereits als Docker-Container laufende Ollama wird verwendet."
    ok "Modelle werden in den Container geladen."
  fi
else
  ok "Ollama wird als Docker-Container bereitgestellt."
  ok "Modelle werden nach dem Start in den Container geladen."
fi

# 5) Docker Compose Pull
title "Pull Docker-Images"
docker compose pull

# 6) Initialstart nur OWUI (Ressourcen anlegen)
title "Initialer Start (Ressourcen anlegen)"
docker compose up -d kommunal-gpt
sleep 20
docker compose down

# 7) DB/Statics kopieren
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

# 8) Gesamtsystem starten
title "Starte System"
docker compose up -d

# 9) Optional: Modelle laden
warn "Die Modelle werden jetzt geladen, dies kann je nach Geschwindigkeit Ihrer Internetverbindung eine Weile dauern!"
if [[ -x "./models.sh" ]]; then
  chmod +x models.sh
  ./models.sh
else
  warn "models.sh nicht ausführbar oder nicht vorhanden."
fi

ok "Setup abgeschlossen."
echo "Sie finden das Dashboard im Browser unter http://localhost."
echo " "
echo "compAInion (Open WebUI) selbst läuft auf Port 3000 dieses Servers"
echo "bitte loggen Sie sich im Browser unter http://localhost:3000"
echo "zur Administration mit folgenden Daten ein:"
echo " "
info "E-Mail: hello@deepmentation.ai"
info "Passwort: CompAdmin#2025!"