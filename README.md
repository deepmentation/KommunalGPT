# KommunalGPT powered by compAInion

KommunalGPT ist Ihr lokaler KI-Assistent für tägliche Arbeiten im Kommunalbereich.

## SYSTEMVORAUSSETZUNGEN

### Administrationsrechte

Das Setup von KommunalGPT erfordert Administrationsrechte (Linux sudo, Windows Admin) auf Ihrem System für die Installation von Docker.

### Systemvoraussetzungen

KommunalGPT ist ein lokal laufender KI-Assistent, d.h die Sprachmodelle werden auf Ihrer Hardware ausgeführt. Damit dies in ausreichender Performance läuft, empfehlen wir folgende Systemvoraussetzungen:

| Komponente | Empfehlung für bis zu 20 gleichzeitige Benutzer | für bis zu 50 gleichzeitige Benutzer | für bis zu 100 gleichzeitige Benutzer |
| --- | --- | --- | --- |
| RAM | 16GB | 32GB | 64GB |
| CPU Kerne | 4 | 8 | 16 |
| Festplattenspeicher | 500GB | 1TB | 2TB |
| Grafikkarte | z.B. Nvidia RTX 4060 Ti | z.B. Nvidia RTX 4090 | z.B. Nvidia RTX A6000 oder 2 x RTX 4090 |
| Grafikkarten-VRAM | 16GB | 24GB | 48GB |
| Bauart | z.B. Workstation | Workstation oder Server | Rack-Server |

Für eine zufriedenstellende Nutzererfahrung empfehlen wir immer den Einsatz CUDA-fähiger Grafikkarten von Nvidia, die mindestens 16GB VRAM haben und somit in guter Geschwindigkeit die Nutzeranfragen verarbeiten können.

---

## INSTALLATION

### 0. Die Setup-Dateien aus den Releases laden und entpacken

Laden Sie den aktuellen Release aus diesem Repository manuell herunter und entpacken es oder nutzen Sie die folgenden Befehle für Download und Entpacken:

**Linux CLI (z.B. Ubuntu):**

```bash
wget https://github.com/deepmentation/KommunalGPT/releases/download/v[VERSION]/KommunalGPT-linux-[VERSION].zip
unzip KommunalGPT-linux-[VERSION].zip -d KommunalGPT
cd KommunalGPT
```

**Windows PowerShell:**

```powershell
Invoke-WebRequest -Uri "https://github.com/deepmentation/KommunalGPT/releases/download/v[VERSION]/KommunalGPT-windows-[VERSION].zip" -OutFile "KommunalGPT-windows-[VERSION].zip"
Expand-Archive -Path "KommunalGPT-windows-[VERSION].zip" -DestinationPath "KommunalGPT"
cd KommunalGPT
```

### 1. Setup ausführen

**Linux:**

```bash
chmod +x setup.sh
bash setup.sh
```

**Windows PowerShell:**

```powershell
setup.bat
```

#### 1.1. Was wird installiert?

- Docker als Container-Engine
- Ollama als Provider für die Sprachmodelle (in einem Docker-Container)
- Download der für KommunalGPT notwendigen Sprachmodelle in Ollama
- KommunalGPT powered by compAInion als Frontend, basierend auf Open-WebUI (in einem Docker-Container)
- Apache Tika als Dokumentenverarbeitung (in einem Docker-Container)
- compAInion-UI als Frontend zur leichteren Nutzung (in einem Docker-Container)

---

## NUTZUNG

### 1. Start

KommunalGPT wird nach der Installation automatisch ausgeführt.  
Nach Neustart des Servers muss KommunalGPT manuell gestartet werden.

```bash
cd KommunalGPT
docker compose up -d
```

Login für Administration: `admin@deepmentation.ai`

Passwort für Administration: `CompAdmin#2025!`

### 2. Stop

```bash
cd KommunalGPT
docker compose down
```

### 3. Update

```bash
cd KommunalGPT
docker compose down
docker compose pull
docker compose up -d
```

Erklärung:
- `cd KommunalGPT`: Wechsel zum Verzeichnis KommunalGPT
- `docker compose down`: Stoppe KommunalGPT
- `docker compose pull`: Lädt die neuesten Container
- `docker compose up -d`: Starte KommunalGPT

### 4. Modelle und deren Funktion

siehe [MODELS.md](MODELS.md)

## Lizenzen & Drittanbieter

- Dieses Repository steht unter der Lizenz: siehe [LICENSE](LICENSE) (Apache-2.0).
- Drittanbieter-Hinweise: siehe [NOTICE](NOTICE).
- Vollständige Lizenztexte der eingebundenen Komponenten: siehe [Licenses.md](Licenses.md).

Eingesetzte Komponenten:
- Open WebUI
- Ollama
- Apache Tika
- compAInion-UI

## Nutzungsbedingungen

siehe [Nutzungsbedingungen](Nutzungsbedingungen.md)


