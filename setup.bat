@echo off
setlocal enabledelayedexpansion

echo === Kommunal-GPT Setup (Windows) ===

REM 1) Name abfragen
set "DEFAULT_NAME=Kommunal-GPT"
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
  echo Docker nicht gefunden.
  choice /M "Soll Docker Desktop via winget installiert werden?"
  if errorlevel 1 (
    winget install -e --id Docker.DockerDesktop
    echo Bitte Docker Desktop starten, ggf. Logout/Login.
  ) else (
    echo Bitte installiere Docker Desktop manuell und starte dieses Skript erneut.
    goto :end
  )
) else (
  for /f "tokens=*" %%v in ('docker --version') do set DOCKERV=%%v
  echo Docker gefunden: %DOCKERV%
)

REM 4) Pull Images
echo Pull Images...
docker compose pull || goto :error

REM 5) Initialstart nur Frontend
echo Initialstart...
docker compose up -d kommunal-gpt-frontend || goto :error
timeout /t 25 /nobreak >nul
docker compose down

REM 6) DB/Statics kopieren
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

REM 7) System starten
echo Starte System...
docker compose up -d || goto :error

REM 8) Optional Modelle laden
choice /M "Die Sprachmodelle werden jetzt geladen, dies kann je nach Geschwindigkeit Ihrer Internetverbindung eine Weile dauern..."
if errorlevel 1 (
  if exist models.bat (
    call models.bat
  ) else (
    echo models.bat nicht gefunden – uebersprungen.
  )
)

echo Setup abgeschlossen.
echo Bitte loggen Sie sich im Browser unter http://localhost:3000 ein.
echo E-Mail: admin@deepmentation.ai
echo Passwort: CompAdmin#2025!
goto :end

:error
echo Fehler beim Ausfuehren eines Docker-Befehls. Bitte Ausgabe pruefen.
:end
endlocal