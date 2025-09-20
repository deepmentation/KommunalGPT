@echo off
setlocal enabledelayedexpansion

set MODELS="llama3.1:8b gemma3:12b qwen3:14b gpt-oss:20b qwen2.5-coder:14b llava:13b"
set MODELS=%MODELS:"=%

REM Erkenne Ollama-Installation (Docker vs. lokal)
set OLLAMA_TYPE=none

REM Prüfe auf Docker-Container
for /f "delims=" %%C in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /i "^ollama$"') do (
    set OLLAMA_TYPE=docker
    goto :type_detected
)

REM Prüfe auf lokale Installation
where ollama >nul 2>nul
if not errorlevel 1 (
    curl -s http://localhost:11434/api/version >nul 2>nul
    if not errorlevel 1 (
        set OLLAMA_TYPE=local
    )
)

:type_detected
if "%OLLAMA_TYPE%"=="docker" (
    echo Docker Ollama-Container erkannt. Lade Modelle in Container...
) else if "%OLLAMA_TYPE%"=="local" (
    echo Lokale Ollama-Installation erkannt. Lade Modelle lokal...
) else (
    echo Keine funktionierende Ollama-Installation gefunden.
    echo Bitte starten Sie zuerst das Setup oder stellen Sie sicher, dass Ollama laeuft.
    goto :end
)

for %%M in (%MODELS%) do (
    echo Downloading model: %%M...
    
    if "%OLLAMA_TYPE%"=="docker" (
        REM Modelle im Docker-Container laden
        for /f "delims=" %%C in ('docker ps --format "{{.Names}}" ^| findstr /i "^ollama$"') do set CONTAINER=%%C
        if not defined CONTAINER (
            echo Ollama-Container laeuft nicht. Starte temporaer...
            docker compose up -d ollama
            timeout /t 5 /nobreak >nul
        )
        docker exec -i ollama ollama pull "%%M"
    ) else if "%OLLAMA_TYPE%"=="local" (
        REM Modelle direkt mit lokaler Installation laden
        ollama pull "%%M"
    )
    
    if errorlevel 1 (
        echo Error downloading: %%M
    ) else (
        echo Finished downloading: %%M
    )
    echo -----------------------------------
)

endlocal