#!/bin/bash

MODELS="llama3.1:8b \
gemma3:12b \
qwen3:14b \
gpt-oss:20b \
qwen2.5-coder:14b \
llava:13b"

# Erkenne Ollama-Installation (Docker vs. lokal)
detect_ollama_type() {
  if docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
    echo "docker"
  elif command -v ollama >/dev/null 2>&1 && curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
    echo "local"
  else
    echo "none"
  fi
}

OLLAMA_TYPE=$(detect_ollama_type)

case "$OLLAMA_TYPE" in
  "docker")
    echo "🐳 Ollama Docker-Container erkannt. Lade Modelle in Container..."
    ;;
  "local")
    echo "💻 Lokale Ollama-Installation erkannt. Lade Modelle lokal..."
    ;;
  "none")
    echo "❌ Keine funktionierende Ollama-Installation gefunden."
    echo "Bitte starten Sie zuerst das Setup oder stellen Sie sicher, dass Ollama läuft."
    exit 1
    ;;
esac

for MODEL in $MODELS; do
  echo "🔄 Downloading model: $MODEL..."
  
  case "$OLLAMA_TYPE" in
    "docker")
      # Modelle innerhalb des laufenden Ollama-Containers ziehen
      if docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
        docker exec -it ollama ollama pull "$MODEL"
      else
        echo "⚠️  Ollama-Container läuft nicht. Starte temporär..."
        docker compose up -d ollama
        sleep 5
        docker exec -it ollama ollama pull "$MODEL"
      fi
      ;;
    "local")
      # Modelle direkt mit lokaler Ollama-Installation laden
      ollama pull "$MODEL"
      ;;
  esac
  
  if [ $? -ne 0 ]; then
    echo "❌ Error downloading: $MODEL"
  else
    echo "✅ Finished downloading: $MODEL"
  fi
  echo "-----------------------------------"
done