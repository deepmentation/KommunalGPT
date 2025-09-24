# KommunalGPT Setup (Windows PowerShell)
# Requires PowerShell 5.1 or higher

param(
    [string]$GPTName = ""
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Helper functions
function Write-Title {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

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

function Get-UserChoice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$DefaultChoice = 1
    )
    
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Length; $i++) {
        Write-Host "$($i + 1)) $($Options[$i])"
    }
    
    do {
        $choice = Read-Host "Ihre Wahl [1-$($Options.Length)]"
        if ([string]::IsNullOrEmpty($choice)) {
            $choice = $DefaultChoice
        }
        try {
            $choiceInt = [int]$choice
            if ($choiceInt -ge 1 -and $choiceInt -le $Options.Length) {
                return $choiceInt
            }
        }
        catch {
            # Invalid input, continue loop
        }
        Write-Warning "Ungueltiger Eingabe. Bitte waehlen Sie eine Zahl zwischen 1 und $($Options.Length)."
    } while ($true)
}

# Main setup script
try {
    Write-Host "=== KommunalGPT Setup (Windows PowerShell) ===" -ForegroundColor Magenta

    # 1) Name abfragen
    Write-Title "Konfiguration"
    $defaultName = "KommunalGPT"
    
    if ([string]::IsNullOrEmpty($GPTName)) {
        $GPTName = Read-Host "Wie soll Ihr GPT heissen? [$defaultName]"
        if ([string]::IsNullOrEmpty($GPTName)) {
            $GPTName = $defaultName
        }
    }
    
    Write-Success "Name gesetzt: $GPTName"

    # 2) .env erstellen/aktualisieren
    Write-Title "Konfiguriere .env"
    
    if (-not (Test-Path ".env")) {
        if (Test-Path ".env.example") {
            Copy-Item ".env.example" ".env"
        } else {
            New-Item -Path ".env" -ItemType File | Out-Null
        }
    }

    # .env Datei aktualisieren
    $envContent = @()
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
    }

    # COMPAINION_NAME setzen/ersetzen
    $GPTNameSet = $false
    $ollamaUrlSet = $false
    
    for ($i = 0; $i -lt $envContent.Length; $i++) {
        if ($envContent[$i] -match "^COMPAINION_NAME=") {
            $envContent[$i] = "COMPAINION_NAME='$GPTName'"
            $GPTNameSet = $true
        }
        elseif ($envContent[$i] -match "^OLLAMA_BASE_URL=") {
            $envContent[$i] = "OLLAMA_BASE_URL='http://localhost:11434'"
            $ollamaUrlSet = $true
        }
    }
    
    if (-not $GPTNameSet) {
        $envContent += "COMPAINION_NAME='$GPTName'"
    }
    if (-not $ollamaUrlSet) {
        $envContent += "OLLAMA_BASE_URL='http://localhost:11434'"
    }
    
    $envContent | Set-Content ".env"
    Write-Success ".env aktualisiert"

    # 3) Docker pruefen/installieren
    Write-Title "Pruefe/Installiere Docker"
    
    if (-not (Test-CommandExists "docker")) {
        Write-Warning "Docker wurde noch nicht auf dem System gefunden."
        
        $dockerOptions = @(
            "Automatische Installation durch Setup",
            "Docker selbst installieren und Setup spaeter erneut starten"
        )
        
        $dockerChoice = Get-UserChoice -Prompt "Moechten Sie eine automatische Installation durch dieses Setup durchfuehren lassen oder Docker selbst installieren?" -Options $dockerOptions
        
        switch ($dockerChoice) {
            1 {
                Write-Info "Installiere Docker Desktop via winget..."
                try {
                    winget install -e --id Docker.DockerDesktop
                    Write-Success "Docker Desktop wurde installiert."
                    Write-Info "Bitte Docker Desktop starten, ggf. Logout/Login erforderlich."
                    Read-Host "Druecken Sie Enter, wenn Docker Desktop gestartet ist"
                }
                catch {
                    Write-Error "Fehler bei der Docker-Installation. Bitte Docker Desktop manuell installieren."
                    Write-Info "Download: https://www.docker.com/products/docker-desktop/"
                    exit 1
                }
            }
            2 {
                Write-Info "Bitte installieren Sie Docker Desktop manuell und starten Sie dieses Setup anschliessend erneut."
                Write-Info "Download: https://www.docker.com/products/docker-desktop/"
                exit 0
            }
        }
    } else {
        Write-Success "Docker wurde bereits auf dem System gefunden, Installation von Docker wird uebersprungen."
        $dockerVersion = docker --version
        Write-Success "Docker Version: $dockerVersion"
    }

    # 4) Ollama pruefen/installieren
    Write-Title "Pruefe/Installiere Ollama"
    
    $ollamaRunning = $false
    $ollamaType = "unknown"
    
    # Pruefe ob Ollama API bereits erreichbar ist
    if (Test-OllamaAPI) {
        $ollamaRunning = $true
        Write-Success "Ollama API ist bereits erreichbar"
        
        # Pruefe ob es ein Docker-Container ist
        try {
            $containers = docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -eq "ollama" }
            if ($containers) {
                Write-Success "Ollama laeuft bereits als Docker-Container"
                $ollamaType = "docker"
            } else {
                Write-Success "Ollama laeuft lokal auf dem System"
                $ollamaType = "local"
            }
        }
        catch {
            Write-Success "Ollama laeuft lokal auf dem System"
            $ollamaType = "local"
        }
    }
    elseif (Test-CommandExists "ollama") {
        Write-Info "Ollama ist installiert, aber API nicht erreichbar. Starte Ollama..."
        try {
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep -Seconds 5
            
            if (Test-OllamaAPI) {
                $ollamaRunning = $true
                $ollamaType = "local"
                Write-Success "Ollama erfolgreich gestartet"
            } else {
                Write-Warning "Ollama konnte nicht gestartet werden. Verwende Docker-Container."
                $ollamaType = "docker"
            }
        }
        catch {
            Write-Warning "Ollama konnte nicht gestartet werden. Verwende Docker-Container."
            $ollamaType = "docker"
        }
    } else {
        Write-Info "Ollama wurde noch nicht auf dem System gefunden."
        Write-Info "Das Setup wird Ollama als Docker-Container bereitstellen."
        $ollamaType = "docker"
    }

    # Informiere ueber Modell-Installation
    if ($ollamaRunning) {
        if ($ollamaType -eq "local") {
            Write-Success "Hinweis: Das bereits lokal installierte Ollama wird verwendet."
            Write-Warning "Die Modelle werden in die lokale Ollama-Installation geladen."
            Write-Warning "Das models.ps1 Skript wird entsprechend angepasst ausgefuehrt."
        } else {
            Write-Success "Hinweis: Das bereits als Docker-Container laufende Ollama wird verwendet."
            Write-Success "Modelle werden in den Container geladen."
        }
    } else {
        Write-Success "Ollama wird als Docker-Container bereitgestellt."
        Write-Success "Modelle werden nach dem Start in den Container geladen."
    }

    # 5) Pull Images
    Write-Title "Pull Docker-Images"
    try {
        docker compose pull
        Write-Success "Docker Images erfolgreich geladen"
    }
    catch {
        Write-Error "Fehler beim Laden der Docker Images"
        throw
    }

    # 6) Initialstart nur Frontend
    Write-Title "Initialer Start (Ressourcen anlegen)"
    try {
        docker compose up -d kommunal-gpt
        Start-Sleep -Seconds 25
        docker compose down
        Write-Success "Initiale Ressourcen erfolgreich angelegt"
    }
    catch {
        Write-Error "Fehler beim initialen Start"
        throw
    }

    # 7) DB/Statics kopieren
    Write-Title "Standard-Datenbank einsetzen"
    
    # Verzeichnisse erstellen
    if (-not (Test-Path "owui\data")) {
        New-Item -Path "owui\data" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path "owui\static")) {
        New-Item -Path "owui\static" -ItemType Directory -Force | Out-Null
    }

    # Datenbank kopieren
    if (Test-Path "master-webui.db") {
        Copy-Item "master-webui.db" "owui\data\webui.db" -Force
        Write-Success "DB eingesetzt: owui\data\webui.db"
    } else {
        Write-Warning "master-webui.db nicht gefunden - uebersprungen."
    }

    # Static files kopieren
    if (Test-Path "static") {
        try {
            Copy-Item "static\*" "owui\static\" -Recurse -Force
            Write-Success "Konfiguration eingespielt"
        }
        catch {
            Write-Warning "Fehler beim Kopieren der Static-Dateien"
        }
    } else {
        Write-Warning "static-Verzeichnis nicht gefunden - uebersprungen."
    }

    # 8) System starten
    Write-Title "Starte System"
    try {
        docker compose up -d
        Write-Success "System erfolgreich gestartet"
    }
    catch {
        Write-Error "Fehler beim Starten des Systems"
        throw
    }

    # 9) Optional: Modelle laden
    Write-Title "Modelle laden"
    Write-Warning "Die Sprachmodelle werden jetzt geladen, dies kann je nach Geschwindigkeit Ihrer Internetverbindung eine Weile dauern!"
    
    $loadModels = Read-Host "Moechten Sie die Modelle jetzt laden? (J/n)"
    if ([string]::IsNullOrEmpty($loadModels) -or $loadModels -match "^[JjYy]") {
        if (Test-Path "models.ps1") {
            Write-Info "Starte models.ps1..."
            & ".\models.ps1"
        }
        elseif (Test-Path "models.bat") {
            Write-Info "Starte models.bat..."
            & ".\models.bat"
        }
        else {
            Write-Warning "Weder models.ps1 noch models.bat gefunden - uebersprungen."
        }
    }

    # Setup abgeschlossen
    Write-Title "Setup abgeschlossen"
    Write-Success "Setup erfolgreich abgeschlossen!"
    Write-Host ""
    Write-Info "Sie finden das Dashboard im Browser unter http://localhost"
    Write-Host ""
    Write-Info "compAInion (Open WebUI) selbst laeuft auf Port 3000 dieses Servers"
    Write-Info "bitte loggen Sie sich im Browser unter http://localhost:3000"
    Write-Info "zur Administration mit folgenden Daten ein:"
    Write-Host ""
    Write-Success "E-Mail: admin@deepmentation.ai"
    Write-Success "Passwort: CompAdmin#2025!"

}
catch {
    Write-Error "Fehler beim Ausfuehren des Setups: $($_.Exception.Message)"
    Write-Host "Bitte ueberpruefen Sie die Ausgabe und versuchen Sie es erneut." -ForegroundColor Red
    exit 1
}
