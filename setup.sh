#!/usr/bin/env bash
set -euo pipefail

title() { echo -e "\n=== $* ==="; }
warn()  { echo -e "⚠️  $*"; }
info()  { echo -e "➡️  $*"; }
ok()    { echo -e "✅ $*"; }

echo "=== KommunalGPT Setup (Linux) ==="

# Funktion: Port-Prüfung
check_port() {
  local port=$1
  if command -v lsof >/dev/null 2>&1; then
    lsof -i :"$port" >/dev/null 2>&1
    return $?
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tuln | grep -q ":$port "
    return $?
  elif command -v ss >/dev/null 2>&1; then
    ss -tuln | grep -q ":$port "
    return $?
  else
    warn "Keine Port-Prüfung möglich (lsof/netstat/ss nicht gefunden)"
    return 1
  fi
}

# Funktion: Alternativen Port abfragen
ask_alternative_port() {
  local service=$1
  local default_port=$2
  local new_port
  
  while true; do
    read -rp "Port für $service [Vorschlag: $default_port]: " new_port
    new_port="${new_port:-$default_port}"
    
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
      warn "Ungültiger Port. Bitte eine Zahl zwischen 1 und 65535 eingeben."
      continue
    fi
    
    if check_port "$new_port"; then
      warn "Port $new_port ist bereits belegt. Bitte einen anderen Port wählen."
      continue
    fi
    
    # Prüfe ob Port bereits von einem anderen Service reserviert wurde
    if [[ "$new_port" == "$OLLAMA_PORT" ]] || [[ "$new_port" == "$WEBUI_PORT" ]] || \
       [[ "$new_port" == "$TIKA_PORT" ]] || [[ "$new_port" == "$COMPAINION_UI_PORT" ]]; then
      warn "Port $new_port wird bereits von einem anderen Service verwendet. Bitte einen anderen Port wählen."
      continue
    fi
    
    echo "$new_port"
    return 0
  done
}

# 1) Name abfragen
DEFAULT_NAME="KommunalGPT"
read -rp "Wie soll dein GPT heißen? [${DEFAULT_NAME}]: " COMPAINION_NAME
COMPAINION_NAME="${COMPAINION_NAME:-$DEFAULT_NAME}"
ok "Name gesetzt: ${COMPAINION_NAME}"

# 2) Port-Prüfung und Konfiguration
title "Prüfe Ports"

# Lese Standard-Ports aus .env.example
if [[ -f ".env.example" ]]; then
  OLLAMA_PORT=$(grep "^OLLAMA_PORT=" .env.example | cut -d'=' -f2)
  WEBUI_PORT=$(grep "^WEBUI_PORT=" .env.example | cut -d'=' -f2)
  TIKA_PORT=$(grep "^TIKA_PORT=" .env.example | cut -d'=' -f2)
  COMPAINION_UI_PORT=$(grep "^COMPAINION_UI_PORT=" .env.example | cut -d'=' -f2)
else
  warn ".env.example nicht gefunden, verwende Standard-Ports"
  OLLAMA_PORT=11434
  WEBUI_PORT=3000
  TIKA_PORT=9998
  COMPAINION_UI_PORT=80
fi

# Prüfe jeden Port
PORTS_CHANGED=false

# Spezielle Prüfung für Ollama-Port
if check_port "$OLLAMA_PORT"; then
  # Port ist belegt - prüfe ob es Ollama ist
  if curl -s http://localhost:${OLLAMA_PORT}/api/version >/dev/null 2>&1; then
    ok "Port $OLLAMA_PORT ist von Ollama belegt - wird verwendet"
  else
    warn "Port $OLLAMA_PORT (Ollama) ist belegt, aber nicht durch Ollama!"
    OLLAMA_PORT=$(ask_alternative_port "Ollama" "11435")
    PORTS_CHANGED=true
    ok "Neuer Ollama-Port: $OLLAMA_PORT"
  fi
else
  ok "Port $OLLAMA_PORT (Ollama) ist frei"
fi

if check_port "$WEBUI_PORT"; then
  warn "Port $WEBUI_PORT (Open WebUI) ist bereits belegt!"
  WEBUI_PORT=$(ask_alternative_port "Open WebUI" "3001")
  PORTS_CHANGED=true
  ok "Neuer Open WebUI-Port: $WEBUI_PORT"
else
  ok "Port $WEBUI_PORT (Open WebUI) ist frei"
fi

if check_port "$TIKA_PORT"; then
  warn "Port $TIKA_PORT (Tika) ist bereits belegt!"
  TIKA_PORT=$(ask_alternative_port "Tika" "9999")
  PORTS_CHANGED=true
  ok "Neuer Tika-Port: $TIKA_PORT"
else
  ok "Port $TIKA_PORT (Tika) ist frei"
fi

if check_port "$COMPAINION_UI_PORT"; then
  warn "Port $COMPAINION_UI_PORT (KommunalGPT-Dashboard) ist bereits belegt!"
  COMPAINION_UI_PORT=$(ask_alternative_port "KommunalGPT-Dashboard" "8080")
  PORTS_CHANGED=true
  ok "Neuer KommunalGPT-Dashboard-Port: $COMPAINION_UI_PORT"
else
  ok "Port $COMPAINION_UI_PORT (KommunalGPT-Dashboard) ist frei"
fi

# Aktualisiere .env.example wenn Ports geändert wurden
if [[ "$PORTS_CHANGED" == "true" ]] && [[ -f ".env.example" ]]; then
  info "Aktualisiere .env.example mit neuen Ports..."
  cp .env.example .env.example.bak
  sed -i.tmp "s|^OLLAMA_PORT=.*|OLLAMA_PORT=$OLLAMA_PORT|g" .env.example
  sed -i.tmp "s|^WEBUI_PORT=.*|WEBUI_PORT=$WEBUI_PORT|g" .env.example
  sed -i.tmp "s|^TIKA_PORT=.*|TIKA_PORT=$TIKA_PORT|g" .env.example
  sed -i.tmp "s|^COMPAINION_UI_PORT=.*|COMPAINION_UI_PORT=$COMPAINION_UI_PORT|g" .env.example
  rm -f .env.example.tmp
  ok ".env.example aktualisiert (Backup: .env.example.bak)"
fi

# 3) .env erstellen/aktualisieren
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
# OLLAMA_BASE_URL setzen/ersetzen (mit dynamischem Port)
if grep -q "^OLLAMA_BASE_URL=" .env; then
  sed -i.bak "s|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL='http://localhost:${OLLAMA_PORT}'|g" .env
else
  echo "OLLAMA_BASE_URL='http://localhost:${OLLAMA_PORT}'" >> .env
fi
rm -f .env.bak
ok ".env aktualisiert"

# 4) Docker installieren/prüfen
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

# 5) Ollama installieren/prüfen
title "Prüfe/Installiere Ollama"

# Prüfe ob Ollama API bereits erreichbar ist
OLLAMA_RUNNING=false
if curl -s http://localhost:${OLLAMA_PORT}/api/version >/dev/null 2>&1; then
  OLLAMA_RUNNING=true
  OLLAMA_VERSION=$(curl -s http://localhost:${OLLAMA_PORT}/api/version 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unbekannt")
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
  
  if curl -s http://localhost:${OLLAMA_PORT}/api/version >/dev/null 2>&1; then
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

# Ollama-Section in docker-compose.yml auskommentieren wenn lokal installiert
if [[ "$OLLAMA_TYPE" == "local" ]]; then
  info "Kommentiere Ollama-Container in docker-compose.yml aus..."
  if [[ -f "docker-compose.yml" ]]; then
    # Backup erstellen
    cp docker-compose.yml docker-compose.yml.bak
    
    # Ollama-Section auskommentieren (Zeilen 6-17)
    sed -i.tmp '6,17s/^/# /' docker-compose.yml
    rm -f docker-compose.yml.tmp
    
    ok "Ollama-Container in docker-compose.yml auskommentiert"
    info "Backup gespeichert als: docker-compose.yml.bak"
  fi
fi

# 6) Docker Compose Pull
title "Pull Docker-Images"
info "Lade Docker Images..."
docker compose pull

# 7) Initialstart nur OWUI (Ressourcen anlegen)
title "Initialer Start (Ressourcen anlegen)"
warn "Es wird nun eventuell das Passwort des Systemadministrators abgefragt. Dieses wird nicht gespeichert, sondern nur zum Kopieren der System-Datenbank benötigt."
docker compose up -d kommunal-gpt
sleep 20
docker compose down

# 8) DB/Statics kopieren
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

# 9) Gesamtsystem starten
title "Starte System"
if [[ "$OLLAMA_TYPE" == "local" ]]; then
  info "Starte System (ohne Ollama-Container, da lokal installiert)..."
else
  info "Starte System mit Ollama-Container..."
fi
docker compose up -d

# 10) Optional: Modelle laden
warn "Die Modelle werden jetzt geladen, dies kann je nach Geschwindigkeit Ihrer Internetverbindung eine Weile dauern!"
if [[ -x "./models.sh" ]]; then
  chmod +x models.sh
  ./models.sh
else
  warn "models.sh nicht ausführbar oder nicht vorhanden."
fi

ok "Setup abgeschlossen."
echo ""
echo "=========================================="
echo "  KommunalGPT ist bereit!"
echo "=========================================="
echo ""
echo "📊 KommunalGPT-Dashboard (Startseite fuer Nutzer):"
echo "   http://localhost:${COMPAINION_UI_PORT}"
echo ""
echo "🔧 KommunalGPT-Dashboard Einstellungen:"
echo "   Admin-Token: $(grep '^COMPAINION_UI_ADMIN_TOKEN=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo 'CompAdmin#2025!')"
echo ""
echo "🤖 Open WebUI (Administration):"
echo "   http://localhost:${WEBUI_PORT}"
echo "   E-Mail: info@KommunalGPT.de"
echo "   Passwort: CompAdmin#2025!"
echo ""
echo "=========================================="