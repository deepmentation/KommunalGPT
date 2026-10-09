#!/bin/bash
# KommunalGPT - Sprachmodelle laden (Linux/macOS)
# Die Liste muss zu den Basismodellen der Assistenten in master-webui.db passen (siehe MODELS.md).

MODELS=(
  "gemma3:12b"                       # ChatBot, Text-Assistenten, Übersetzung, Bildbeschreiber
  "qwen3:14b"                        # Brainstorming, Recherche, Dateninterpretation
  "qwen2.5-coder:14b"                # Code-Unterstützung
  "llama3.2:3b"                      # Chat-Titel und Autovervollständigung
  "jina/jina-embeddings-v2-base-de"  # Dokumente / Wissensdatenbanken (Embedding)
)

# Erkenne Ollama-Installation (Docker vs. lokal)
detect_ollama_type() {
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^ollama$'; then
    echo "docker"
  elif command -v ollama >/dev/null 2>&1 && curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
    echo "local"
  else
    echo "none"
  fi
}

OLLAMA_TYPE=$(detect_ollama_type)

case "$OLLAMA_TYPE" in
  "docker") echo "🐳 Ollama Docker-Container erkannt. Lade Modelle in den Container..." ;;
  "local")  echo "💻 Lokale Ollama-Installation erkannt. Lade Modelle lokal..." ;;
  "none")
    echo "❌ Keine funktionierende Ollama-Installation gefunden."
    echo "Bitte starten Sie zuerst das Setup oder stellen Sie sicher, dass Ollama läuft."
    exit 1
    ;;
esac

FAILED=()
for MODEL in "${MODELS[@]}"; do
  echo "🔄 Lade Modell: $MODEL ..."
  if [[ "$OLLAMA_TYPE" == "docker" ]]; then
    # Kein -t: funktioniert auch, wenn das Skript nicht in einem Terminal laeuft
    docker exec ollama ollama pull "$MODEL"
  else
    ollama pull "$MODEL"
  fi
  if [[ $? -eq 0 ]]; then
    echo "✅ Fertig: $MODEL"
  else
    echo "❌ Fehler beim Laden: $MODEL"
    FAILED+=("$MODEL")
  fi
  echo "-----------------------------------"
done

echo ""
echo "=== Zusammenfassung ==="
echo "Erfolgreich: $(( ${#MODELS[@]} - ${#FAILED[@]} )) von ${#MODELS[@]} Modellen"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "❌ Fehlgeschlagen:"
  for MODEL in "${FAILED[@]}"; do echo "   - $MODEL"; done
  echo "Bitte Internetverbindung pruefen und ./models.sh erneut ausfuehren."
  exit 1
fi
echo "✅ Alle Modelle geladen."
