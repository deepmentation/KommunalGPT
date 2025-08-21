# Kommunal-GPT powered by compAInion

Kommunal-GPT ist Ihr lokaler KI-Assistent für tägliche Arbeiten im Kommunalbereich.

## SYSTEMVORAUSSETZUNGEN

### Administrationsrechte

Das Setup von Kommunal-GPT erfordert Administrationsrechte auf Ihrem System.

### Systemvoraussetzungen

Kommunal-GPT ist ein lokal laufender KI-Assistent, d.h die Sprachmodelle werden auf Ihrer Hardware ausgeführt. Damit dies in ausreichender Performance läuft, empfehlen wir folgende Systemvoraussetzungen:

| Komponente | Empfehlung für bis zu 20 gleichzeitige Benutzer | für bis zu 50 gleichzeitige Benutzer | für bis zu 100 gleichzeitige Benutzer |
| --- | --- | --- | --- |
| RAM | 16GB | 32GB | 64GB |
| CPU Kerne | 4 | 8 | 16 |
| Festplattenspeicher | 500GB | 1TB | 2TB |
| Grafikkarte | z.B. Nvidia RTX 4060 Ti | z.B. Nvidia RTX 4090 | z.B. Nvidia RTX A6000 oder 2 x RTX 4090 |
| Grafikkarten-VRAM | 16GB | 24GB | 48GB |
| Bauart | z.B. Workstation | Workstation oder Server | Rack-Server |

Für eine zufriedenstellende Nutzererfahrung empfehlen wir immer den Einsatz CUDA-fähiger Grafikkarten von Nvidia, die mindestens 16GB VRAM haben und somit in guter Geschwindigkeit die Nutzeranfragen verarbeiten können.

## INSTALLATION

### 0. Die Setup-Dateien aus den Releases laden

### 1. Setup ausführen

Linux:

```bash
./setup.sh
```

Windows:

```bash
setup.bat
```

#### 1.1. Was wird installiert?

- Docker als Container-Engine
- Ollama als Provider für die Sprachmodelle (in einem Docker-Container)
- Download der für Kommunal-GPT notwendigen Sprachmodelle in Ollama
- Kommunal-GPT powered by compAInion als Frontend, basierend auf Open-WebUI (in einem Docker-Container)

#### 1.2. Modelle laden

Linux:
```bash
chmod +x models.sh
bash models.sh
```

Windows: `models.bat`

### 1.3. Erster Start zum Ressourcen anlegen

*(Startet nur das compAInion Frontend)*

`docker compose up`

`docker compose down`

### 1.4. Standard-Datenbank einsetzen

Linux: `cp master-webui.db owui/data/webui.db`

Windows: `copy master-webui.db owui\data\webui.db`

*(Bei Nachfrage, vorhandene Dateien ersetzen)*

### 1.5. Statics ersetzen

Linux: `cp static/*.* owui/static`

Windows: `copy static/*.* owui/static`

*(Bei Nachfrage, vorhandene Dateien ersetzen)*

## NUTZUNG

### 1. Start

`docker compose up -d`

Login für Administration: `admin@deepmentation.ai`

Passwort für Administration: `CompAdmin#2025!`

### 2. Stop

`docker compose down`

### 3. Update

```
docker compose down
docker compose pull
docker compose up -d
```

### 4. Modelle und deren Funktion

siehe MODELS.md

## Lizenzen & Drittanbieter

- Dieses Repository steht unter der Lizenz: siehe `LICENSE` (Apache-2.0).
- Drittanbieter-Hinweise: siehe `NOTICE`.
- Vollständige Lizenztexte der eingebundenen Komponenten: siehe `Licenses.md`.

Eingesetzte Komponenten:
- Open WebUI (BSD 3-Clause mit zusätzlicher Branding-Klausel)
  - Hinweis: Entfernen/Ändern von "Open WebUI"-Branding ist nur in begrenzten Fällen erlaubt (≤ 50 Endnutzer in 30 Tagen, ausdrückliche Erlaubnis oder Enterprise-Lizenz). Bitte beachtet dies insbesondere bei Anpassungen im Ordner `static/`.
- Ollama (MIT)
- Apache Tika (Apache-2.0)
