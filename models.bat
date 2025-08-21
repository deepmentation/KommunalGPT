@echo off
setlocal enabledelayedexpansion

set MODELS="llama3.1:8b gemma3:12b qwen2.5:latest deepseek-r1:8b qwen2.5-coder:14b granite3.2-vision:latest"

set MODELS=%MODELS:"=%

for %%M in (%MODELS%) do (
    echo Downloading model: %%M...
    rem Modelle im laufenden Ollama-Container ziehen; wenn Container nicht läuft, kurz starten
    for /f "delims=" %%C in ('docker ps --format "{{.Names}}" ^| findstr /i "^ollama$"') do set CONTAINER=%%C
    if not defined CONTAINER (
        echo Ollama-Container laeuft nicht. Starte temporaer...
        docker compose up -d ollama
        timeout /t 5 /nobreak >nul
    )
    docker exec -i ollama ollama pull "%%M"
    if errorlevel 1 (
        echo Error downloading: %%M
    ) else (
        echo Finished downloading: %%M
    )
    echo -----------------------------------
)

endlocal