@echo off
setlocal enabledelayedexpansion

echo === KommunalGPT Setup (Windows) ===

REM 1) Name abfragen
set "DEFAULT_NAME=KommunalGPT"
set /p COMPAINION_NAME=Wie soll dein GPT heissen? [%DEFAULT_NAME%]: 
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
powershell -NoProfile -Command ^
  "$envPath='.env';" ^
  "$c=Get-Content $envPath; " ^
  "if($c -match '^COMPAINION_NAME='){ $c=$c -replace '^COMPAINION_NAME=.*', 'COMPAINION_NAME='''%COMPAINION_NAME%''' } else { $c+=\"`nCOMPAINION_NAME=''%COMPAINION_NAME%''\" };" ^
  "if($c -match '^OLLAMA_BASE_URL='){ $c=$c -replace '^OLLAMA_BASE_URL=.*', 'OLLAMA_BASE_URL=''http://localhost:11434''' } else { $c+=\"`nOLLAMA_BASE_URL=''http://localhost:11434''\" };" ^
  "Set-Content -NoNewline -Path $envPath -Value ($c -join \"`n\")"
echo .env aktualisiert.

REM 3) Docker pruefen/Installieren
where docker >nul 2>nul
if errorlevel 1 (
  echo Docker wurde noch nicht auf dem System gefunden.
  echo Moechten Sie eine automatische Installation durch dieses Setup durchfuehren lassen
  echo oder Docker selbst installieren und anschliessend dieses Setup erneut starten?
  echo.
  echo 1) Automatische Installation durch Setup
  echo 2) Docker selbst installieren und Setup spaeter erneut starten
  echo.
  choice /C 12 /M "Ihre Wahl"
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
where ollama >nul 2>nul
if errorlevel 1 (
  echo Ollama wurde noch nicht auf dem System gefunden.
  echo Moechten Sie eine automatische Installation durch dieses Setup durchfuehren lassen
  echo oder Ollama selbst installieren und anschliessend dieses Setup erneut starten?
  echo.
  echo 1) Automatische Installation durch Setup
  echo 2) Ollama selbst installieren und Setup spaeter erneut starten
  echo.
  choice /C 12 /M "Ihre Wahl"
  if errorlevel 2 (
    echo Bitte installieren Sie Ollama manuell und starten Sie dieses Setup anschliessend erneut.
    echo Download: https://ollama.com/download
    goto :end
  )
  if errorlevel 1 (
    echo Installiere Ollama...
    REM Versuche zuerst winget
    winget install -e --id Ollama.Ollama
    if errorlevel 1 (
      echo Winget-Installation fehlgeschlagen. Versuche direkten Download...
      REM Fallback: Direkter Download und Installation
      powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile 'OllamaSetup.exe'; " ^
        "Start-Process -FilePath 'OllamaSetup.exe' -Wait; " ^
        "Remove-Item 'OllamaSetup.exe' -Force"
      if errorlevel 1 (
        echo Fehler bei der Ollama-Installation. Bitte Ollama manuell installieren.
        goto :end
      )
    )
    echo Ollama wurde installiert. Starte Ollama-Service...
    REM Ollama Service starten
    start /B ollama serve
    timeout /t 5 /nobreak >nul
  )
) else (
  echo Ollama wurde bereits auf dem System gefunden, Installation von Ollama wird uebersprungen.
  for /f "tokens=*" %%v in ('ollama --version 2^>nul') do set OLLAMAV=%%v
  if defined OLLAMAV (
    echo Ollama Version: %OLLAMAV%
  ) else (
    echo Ollama Version: Version nicht verfuegbar
  )
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