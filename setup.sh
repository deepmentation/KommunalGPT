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
# WICHTIG: Der gewaehlte Port wird ueber stdout zurueckgegeben und per Command-Substitution
# eingefangen. Alle Meldungen muessen deshalb nach stderr gehen, sonst landen sie im Portwert.
ask_alternative_port() {
  local service=$1
  local default_port=$2
  local new_port

  while true; do
    read -rp "Port für $service [Vorschlag: $default_port]: " new_port >&2
    new_port="${new_port:-$default_port}"

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
      warn "Ungültiger Port. Bitte eine Zahl zwischen 1 und 65535 eingeben." >&2
      continue
    fi

    if check_port "$new_port"; then
      warn "Port $new_port ist bereits belegt. Bitte einen anderen Port wählen." >&2
      continue
    fi

    # Prüfe ob Port bereits von einem anderen Service reserviert wurde
    if [[ "$new_port" == "$OLLAMA_PORT" ]] || [[ "$new_port" == "$WEBUI_PORT" ]] || \
       [[ "$new_port" == "$TIKA_PORT" ]] || [[ "$new_port" == "$COMPAINION_UI_PORT" ]]; then
      warn "Port $new_port wird bereits von einem anderen Service verwendet. Bitte einen anderen Port wählen." >&2
      continue
    fi

    echo "$new_port"
    return 0
  done
}

# Funktion: Schluessel=Wert in der .env setzen (anlegen oder ersetzen)
set_env() {
  local key=$1
  local value=$2
  touch .env
  if grep -q "^${key}=" .env; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|g" .env
    rm -f .env.bak
  else
    echo "${key}=${value}" >> .env
  fi
}

# Funktion: primaere IP des Hosts ermitteln (Linux und macOS), Rueckfall auf localhost.
# Darf unter "set -euo pipefail" niemals fehlschlagen - "hostname -I" gibt es z. B. nur unter Linux.
detect_host_ip() {
  local ip=""
  if ip="$(hostname -I 2>/dev/null)"; then
    ip="$(echo "$ip" | awk '{print $1}')"
  else
    ip=""
  fi
  if [[ -z "$ip" ]] && command -v ipconfig >/dev/null 2>&1; then
    ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  fi
  echo "${ip:-localhost}"
}

# Funktion: Wert aus einer env-Datei lesen
get_env_value() {
  local key=$1
  local file=$2
  grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d "'\"" || true
}

# 1) Name abfragen
DEFAULT_NAME="KommunalGPT"
read -rp "Wie soll dein GPT heißen? [${DEFAULT_NAME}]: " COMPAINION_NAME
COMPAINION_NAME="${COMPAINION_NAME:-$DEFAULT_NAME}"
ok "Name gesetzt: ${COMPAINION_NAME}"

# 2) .env anlegen (vor der Port-Pruefung, damit die Ports direkt dort landen)
title "Konfiguriere .env"
if [[ ! -f ".env" ]]; then
  if [[ -f ".env.example" ]]; then
    cp .env.example .env
    ok ".env aus .env.example erstellt"
  else
    touch .env
    warn ".env.example nicht gefunden - leere .env angelegt"
  fi
else
  ok "Bestehende .env wird weiterverwendet"
fi

set_env "COMPAINION_NAME" "'${COMPAINION_NAME}'"

# 3) Port-Prüfung und Konfiguration
title "Prüfe Ports"

# Lese aktuelle Ports aus der .env (nicht aus der versionierten Vorlage .env.example)
OLLAMA_PORT=$(get_env_value "OLLAMA_PORT" .env)
WEBUI_PORT=$(get_env_value "WEBUI_PORT" .env)
TIKA_PORT=$(get_env_value "TIKA_PORT" .env)
COMPAINION_UI_PORT=$(get_env_value "COMPAINION_UI_PORT" .env)

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
WEBUI_PORT="${WEBUI_PORT:-3000}"
TIKA_PORT="${TIKA_PORT:-9998}"
COMPAINION_UI_PORT="${COMPAINION_UI_PORT:-8080}"

# Prüfe jeden Port
PORTS_CHANGED=false

# Spezielle Prüfung für Ollama-Port
# Achtung: Open WebUI spricht Ollama laut mitgelieferter Datenbank fest ueber Port 11434 an.
# Ein Ausweichen auf einen anderen Port wuerde die Anbindung lautlos zerstoeren - deshalb wird
# hier abgebrochen statt umkonfiguriert.
if check_port "$OLLAMA_PORT"; then
  if curl -s http://localhost:${OLLAMA_PORT}/api/version >/dev/null 2>&1; then
    ok "Port $OLLAMA_PORT ist von Ollama belegt - wird verwendet"
  else
    warn "Port $OLLAMA_PORT wird von einem anderen Dienst belegt - nicht von Ollama."
    warn "KommunalGPT benoetigt diesen Port zwingend fuer die Ollama-Anbindung."
    warn "Bitte geben Sie Port $OLLAMA_PORT frei und starten Sie das Setup erneut."
    exit 1
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

# Ports in die .env schreiben (NICHT in die versionierte Vorlage .env.example)
if [[ "$PORTS_CHANGED" == "true" ]]; then
  info "Uebernehme neue Ports in die .env..."
fi
set_env "OLLAMA_PORT" "$OLLAMA_PORT"
set_env "WEBUI_PORT" "$WEBUI_PORT"
set_env "TIKA_PORT" "$TIKA_PORT"
set_env "COMPAINION_UI_PORT" "$COMPAINION_UI_PORT"

# Dashboard-Weiterleitung auf den tatsaechlichen Host setzen, damit der Link auch von
# Arbeitsplatz-Rechnern funktioniert und nicht auf deren eigenen "localhost" zeigt.
DEFAULT_HOST="$(detect_host_ip)"
read -rp "Unter welchem Hostnamen/IP ist dieser Server erreichbar? [${DEFAULT_HOST}]: " SERVER_HOST
SERVER_HOST="${SERVER_HOST:-$DEFAULT_HOST}"
set_env "COMPAINION_DEFAULT_URL" "\"http://${SERVER_HOST}:\${WEBUI_PORT}\""
ok "Dashboard verweist auf http://${SERVER_HOST}:${WEBUI_PORT}"

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

# Ollama-Container per Compose-Profil zu- oder abschalten.
# Frueher wurde die Ollama-Sektion ueber feste Zeilennummern auskommentiert - das zerbrach bei
# jeder Aenderung am Dateikopf. Das Profil "ollama" ist dagegen unabhaengig vom Dateiaufbau.
if [[ "$OLLAMA_TYPE" == "local" ]]; then
  set_env "COMPOSE_PROFILES" ""
  ok "Lokales Ollama wird verwendet - der Ollama-Container bleibt ausgeschaltet."
else
  set_env "COMPOSE_PROFILES" "ollama"
  ok "Ollama wird als Container bereitgestellt (Compose-Profil 'ollama' aktiv)."
fi

# Erreichbarkeit aus einem Container heraus pruefen.
# Open WebUI spricht Ollama als http://host.docker.internal:11434 an. Ein lokal per systemd
# installiertes Ollama lauscht standardmaessig nur auf 127.0.0.1 und ist von dort NICHT
# erreichbar - das faellt sonst erst auf, wenn der erste Nutzer einen leeren Modellkatalog sieht.
if [[ "$OLLAMA_TYPE" == "local" ]]; then
  title "Prüfe Ollama-Erreichbarkeit aus dem Container"
  if docker run --rm --add-host=host.docker.internal:host-gateway curlimages/curl:latest \
       -s --max-time 10 "http://host.docker.internal:${OLLAMA_PORT}/api/version" >/dev/null 2>&1; then
    ok "Ollama ist aus dem Container erreichbar"
  else
    warn "Ollama laeuft lokal, ist aus dem Docker-Container aber NICHT erreichbar."
    warn "Open WebUI wuerde dadurch ohne Modelle starten."
    echo ""
    echo "Ursache: Ollama lauscht vermutlich nur auf 127.0.0.1."
    echo "Abhilfe (Linux/systemd):"
    echo "  sudo systemctl edit ollama"
    echo "  [Service]"
    echo "  Environment=\"OLLAMA_HOST=0.0.0.0\""
    echo "  sudo systemctl restart ollama"
    echo ""
    read -rp "Trotzdem fortfahren? [j/N]: " CONTINUE_ANYWAY
    if [[ ! "$CONTINUE_ANYWAY" =~ ^[jJyY]$ ]]; then
      info "Setup abgebrochen. Bitte Ollama erreichbar machen und erneut starten."
      exit 1
    fi
  fi
fi

# 6) Docker Compose Pull
title "Pull Docker-Images"
info "Lade Docker Images..."
docker compose pull

# 7) Initialstart nur OWUI (Ressourcen anlegen)
title "Initialer Start (Ressourcen anlegen)"
docker compose up -d kommunal-gpt
sleep 20
docker compose down

# 8) Standard-Datenbank einsetzen
# Hinweis: Das Branding von Open WebUI wird bewusst NICHT mehr ueberschrieben. Frueher wurden
# hier static/*.* nach owui/static/ kopiert - das ersetzte Favicon und Splash von Open WebUI und
# stand damit im Konflikt mit dessen Branding-Klausel. Der Name bleibt ueber WEBUI_NAME erhalten.
title "Standard-Datenbank einsetzen"
if [[ -f "master-webui.db" ]]; then
  mkdir -p owui/data
  # Erst ohne sudo versuchen - auf den meisten Systemen gehoert das Verzeichnis dem Benutzer.
  if cp -f master-webui.db owui/data/webui.db 2>/dev/null; then
    ok "DB eingesetzt: owui/data/webui.db"
  else
    warn "Kopieren ohne erweiterte Rechte fehlgeschlagen - versuche es mit sudo."
    warn "Das Passwort wird nicht gespeichert, sondern nur fuer diesen Kopiervorgang benoetigt."
    if sudo cp -f master-webui.db owui/data/webui.db; then
      ok "DB eingesetzt: owui/data/webui.db"
    else
      warn "Die Standard-Datenbank konnte nicht eingesetzt werden."
      warn "Open WebUI wuerde ohne die vorkonfigurierten Assistenten starten. Setup abgebrochen."
      exit 1
    fi
  fi
else
  warn "master-webui.db nicht gefunden – übersprungen."
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
title "Sprachmodelle"
echo "Die Sprachmodelle koennen jetzt geladen werden. Das sind je nach Auswahl mehrere"
echo "Gigabyte und kann eine Weile dauern. Sie koennen das auch spaeter mit ./models.sh nachholen."
read -rp "Modelle jetzt laden? [j/N]: " LOAD_MODELS
if [[ "$LOAD_MODELS" =~ ^[jJyY]$ ]]; then
  if [[ -f "./models.sh" ]]; then
    chmod +x models.sh
    ./models.sh || warn "Beim Laden der Modelle sind Fehler aufgetreten - siehe Ausgabe oben."
  else
    warn "models.sh nicht vorhanden."
  fi
else
  info "Modelle uebersprungen. Nachholen jederzeit mit: ./models.sh"
fi

ok "Setup abgeschlossen."
echo ""
echo "=========================================="
echo "  KommunalGPT ist bereit!"
echo "=========================================="
echo ""
echo "📊 KommunalGPT-Dashboard (Startseite fuer Nutzer):"
echo "   http://${SERVER_HOST}:${COMPAINION_UI_PORT}"
echo ""
echo "🔧 KommunalGPT-Dashboard Einstellungen:"
echo "   Admin-Token: siehe COMPAINION_UI_ADMIN_TOKEN in der Datei .env"
echo ""
echo "🤖 Open WebUI (Administration):"
echo "   http://${SERVER_HOST}:${WEBUI_PORT}"
echo "   E-Mail: info@KommunalGPT.de"
echo ""
echo "⚠️  WICHTIG: Melden Sie sich jetzt an und aendern Sie das Administrator-Passwort."
echo "   Das Auslieferungspasswort ist oeffentlich dokumentiert und auf jeder Installation"
echo "   identisch. Solange es gilt, ist Ihre Installation nicht geschuetzt."
echo ""
echo "=========================================="