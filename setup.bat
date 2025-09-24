@echo off
setlocal enabledelayedexpansion

echo === KommunalGPT Setup (Windows) ===

REM 1) Name abfragen
set "DEFAULT_NAME=KommunalGPT"
set /p COMPAINION_NAME=Wie soll Ihr GPT heissen? [%DEFAULT_NAME%]: 
if "%COMPAINION_NAME%"=="" set "COMPAINION_NAME=%DEFAULT_NAME%"
echo Name gesetzt: %COMPAINION_NAME%

REM 2) .env erstellen/aktualisieren
if not exist ".env" (
  if exist ".env.example" (
    copy /Y ".env.example" ".env" >nul
  ) else (
    type nul > ".env"
  )
)
REM COMPAINION_NAME setzen/ersetzen
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UpdateEnv.ps1" -Name "%COMPAINION_NAME%"
echo .env aktualisiert.

REM 3) Docker pruefen/Installieren
where docker >nul 2>nul
if errorlevel 1 (
  echo Docker wurde noch nicht auf dem System gefunden.
  echo Moechten Sie eine automatische Installation durch dieses Setup durchfuehren lassen
  echo oder Docker selbst installieren und anschliessend dieses Setup erneut starten?
  echo.
  echo 1 - Automatische Installation durch Setup
  echo 2 - Docker selbst installieren und Setup spaeter erneut starten
  echo.
  choice /C 12 /M "Ihre Wahl "
  if errorlevel 2 (
    echo Bitte installieren Sie Docker Desktop manuell und starten Sie dieses Setup anschliessend erneut.
    echo Download: https://www.docker.com/products/docker-desktop/
    goto :end
  )
  if errorlevel 1 (
    echo Installiere Docker Desktop via winget...
    winget install -e --id Docker.DockerDesktop
    if errorlevel 1 (
      echo Fehler bei der Docker-Installation. Bitte Docker Desktop manuell installieren.
      goto :end
    )
    echo Bitte Docker Desktop starten, ggf. Logout/Login erforderlich.
    echo Druecken Sie eine beliebige Taste, wenn Docker Desktop gestartet ist...
    pause >nul
  )
) else (
  echo Docker wurde bereits auf dem System gefunden, Installation von Docker wird uebersprungen.
  for /f "tokens=*" %%v in ('docker --version') do set DOCKERV=%%v
  echo Docker Version: %DOCKERV%
)

REM 4) Ollama pruefen/Installieren
echo Pruefe Ollama-Installation...

REM Pruefe ob Ollama API bereits erreichbar ist
set OLLAMA_RUNNING=false
set OLLAMA_TYPE=unknown

curl -s http://localhost:11434/api/version >nul 2>nul
if not errorlevel 1 (
  set OLLAMA_RUNNING=true
  echo Ollama API ist bereits erreichbar
  
  REM Pruefe ob es ein Docker-Container ist
  for /f "delims=" %%C in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /i "^ollama$"') do (
    echo Ollama laeuft bereits als Docker-Container
    set OLLAMA_TYPE=docker
    goto :ollama_detected
  )
  
  echo Ollama laeuft lokal auf dem System
  set OLLAMA_TYPE=local
  goto :ollama_detected
)

REM Pruefe ob Ollama installiert aber nicht gestartet ist
where ollama >nul 2>nul
if not errorlevel 1 (
  echo Ollama ist installiert, aber API nicht erreichbar. Starte Ollama...
  start /B ollama serve
  timeout /t 5 /nobreak >nul
  
  curl -s http://localhost:11434/api/version >nul 2>nul
  if not errorlevel 1 (
    set OLLAMA_RUNNING=true
    set OLLAMA_TYPE=local
    echo Ollama erfolgreich gestartet
    goto :ollama_detected
  ) else (
    echo Ollama konnte nicht gestartet werden. Verwende Docker-Container.
    set OLLAMA_TYPE=docker
  )
) else (
  echo Ollama wurde noch nicht auf dem System gefunden.
  set OLLAMA_TYPE=docker
)

:ollama_detected
REM Informiere ueber Modell-Installation
if "%OLLAMA_RUNNING%"=="true" (
  if "%OLLAMA_TYPE%"=="local" (
    echo Hinweis: Das bereits lokal installierte Ollama wird verwendet.
    echo Die Modelle werden in die lokale Ollama-Installation geladen.
    echo Das models.bat Skript wird entsprechend angepasst ausgefuehrt.
  ) else (
    echo Hinweis: Das bereits als Docker-Container laufende Ollama wird verwendet.
    echo Modelle werden in den Container geladen.
  )
) else (
  echo Ollama wird als Docker-Container bereitgestellt.
  echo Modelle werden nach dem Start in den Container geladen.
)

REM 5) Pull Images
echo Pull Images...
docker compose pull || goto :error

REM 6) Initialstart nur Frontend
echo Initialstart...
docker compose up -d kommunal-gpt || goto :error
timeout /t 25 /nobreak >nul
docker compose down

REM 7) DB/Statics kopieren
echo Kopiere Standard-Datenbank...
if not exist owui\data mkdir owui\data
if not exist owui\static mkdir owui\static

if exist master-webui.db (
  copy /Y master-webui.db owui\data\webui.db >nul
) else (
  echo master-webui.db nicht gefunden – uebersprungen.
)

REM xcopy fuer rekursives Kopieren alternativ:
if exist static (
  xcopy static\* owui\static\ /Y /I /Q >nul
) else (
  echo static\-Verzeichnis nicht gefunden – uebersprungen.
)

REM 8) System starten
echo Starte System...
docker compose up -d || goto :error

REM 9) Optional Modelle laden
choice /M "Die Sprachmodelle werden jetzt geladen, dies kann je nach Geschwindigkeit Ihrer Internetverbindung eine Weile dauern..."
if errorlevel 1 (
  if exist models.bat (
    call models.bat
  ) else (
    echo models.bat nicht gefunden – uebersprungen.
  )
)

echo Setup abgeschlossen.
echo Sie finden das Dashboard im Browser unter http://localhost.
echo ---
echo compAInion (Open WebUI) selbst läuft auf Port 3000 dieses Servers
echo bitte loggen Sie sich im Browser unter http://localhost:3000
echo zur Administration mit folgenden Daten ein:
echo ---
echo E-Mail: admin@deepmentation.ai
echo Passwort: CompAdmin#2025!
goto :end

:error
echo Fehler beim Ausfuehren eines Docker-Befehls. Bitte Ausgabe pruefen.
:end
endlocal
