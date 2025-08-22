#!/bin/bash

MODELS="llama3.1:8b \
gemma3:12b \
qwen3:14b \
gpt-oss:20b \
qwen2.5-coder:14b \
llava:13b"

for MODEL in $MODELS; do
  echo "🔄 Downloading model: $MODEL..."
  # Modelle innerhalb des laufenden Ollama-Containers ziehen, damit sie im gemounteten Volume landen
  if docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
    docker exec -it ollama ollama pull "$MODEL"
  else
    echo "⚠️  Ollama-Container läuft nicht. Starte temporär..."
    docker compose up -d ollama
    # Warte kurz, bis der Dienst erreichbar ist
    sleep 5
    docker exec -it ollama ollama pull "$MODEL"
  fi
  if [ $? -ne 0 ]; then
    echo "❌ Error downloading: $MODEL"
  else
    echo "✅ Finished downloading: $MODEL"
  fi
  echo "-----------------------------------"
done