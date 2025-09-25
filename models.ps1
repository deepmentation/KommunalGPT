# KommunalGPT Models Download (Windows PowerShell)
# Requires PowerShell 5.1 or higher

# Set error action preference
$ErrorActionPreference = "Stop"

# Model list
$Models = @(
    "llama3.1:8b",
    "gemma3:12b", 
    "qwen3:14b",
    "gpt-oss:20b",
    "qwen2.5-coder:14b",
    "llava:13b",
    "jina/jina-embeddings-v2-base-de"
)

# Helper functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-CommandExists {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-OllamaAPI {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/version" -Method Get -TimeoutSec 5 -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-OllamaType {
    # Pruefe auf Docker-Container
    try {
        $containers = docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "ollama" }
        if ($containers) {
            return "docker"
        }
    }
    catch {
        # Docker-Befehl fehlgeschlagen, ignorieren
    }
    
    # Pruefe auf lokale Installation
    if ((Test-CommandExists "ollama") -and (Test-OllamaAPI)) {
        return "local"
    }
    
    return "none"
}

function Start-OllamaContainer {
    try {
        Write-Warning "Ollama-Container laeuft nicht. Starte temporaer..."
        docker compose up -d ollama
        Start-Sleep -Seconds 5
        return $true
    }
    catch {
        Write-Error "Fehler beim Starten des Ollama-Containers"
        return $false
    }
}

function Download-ModelDocker {
    param([string]$ModelName)
    
    try {
        # Pruefe ob Container laeuft
        $containers = docker ps --format "{{.Names}}" | Where-Object { $_ -eq "ollama" }
        if (-not $containers) {
            if (-not (Start-OllamaContainer)) {
                return $false
            }
        }
        
        # Modell im Container laden
        $result = docker exec -i ollama ollama pull $ModelName
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-Error "Fehler beim Laden des Modells im Docker-Container: $($_.Exception.Message)"
        return $false
    }
}

function Download-ModelLocal {
    param([string]$ModelName)
    
    try {
        ollama pull $ModelName
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-Error "Fehler beim Laden des Modells lokal: $($_.Exception.Message)"
        return $false
    }
}

# Main script
try {
    Write-Host "=== KommunalGPT Models Download ===" -ForegroundColor Magenta
    Write-Host ""

    # Erkenne Ollama-Installation (Docker vs. lokal)
    $ollamaType = Get-OllamaType

    switch ($ollamaType) {
        "docker" {
            Write-Success "Ollama Docker-Container erkannt. Lade Modelle in Container..."
        }
        "local" {
            Write-Success "Lokale Ollama-Installation erkannt. Lade Modelle lokal..."
        }
        "none" {
            Write-Error "Keine funktionierende Ollama-Installation gefunden."
            Write-Info "Bitte starten Sie zuerst das Setup oder stellen Sie sicher, dass Ollama laeuft."
            exit 1
        }
    }

    Write-Host ""
    Write-Info "Folgende Modelle werden geladen:"
    foreach ($model in $Models) {
        Write-Host "  - $model" -ForegroundColor Gray
    }
    Write-Host ""

    $successCount = 0
    $failCount = 0

    # Modelle laden
    foreach ($model in $Models) {
        Write-Info "Downloading model: $model..."
        
        $success = $false
        switch ($ollamaType) {
            "docker" {
                $success = Download-ModelDocker -ModelName $model
            }
            "local" {
                $success = Download-ModelLocal -ModelName $model
            }
        }
        
        if ($success) {
            Write-Success "Finished downloading: $model"
            $successCount++
        } else {
            Write-Error "Error downloading: $model"
            $failCount++
        }
        
        Write-Host "-----------------------------------" -ForegroundColor DarkGray
    }

    # Zusammenfassung
    Write-Host ""
    Write-Host "=== Download-Zusammenfassung ===" -ForegroundColor Magenta
    Write-Success "Erfolgreich geladen: $successCount Modelle"
    
    if ($failCount -gt 0) {
        Write-Warning "Fehlgeschlagen: $failCount Modelle"
        Write-Info "Bitte ueberpruefen Sie die Fehler und versuchen Sie es bei Bedarf erneut."
    } else {
        Write-Success "Alle Modelle erfolgreich geladen!"
    }

}
catch {
    Write-Error "Unerwarteter Fehler beim Laden der Modelle: $($_.Exception.Message)"
    Write-Host "Bitte ueberpruefen Sie die Ausgabe und versuchen Sie es erneut." -ForegroundColor Red
    exit 1
}
