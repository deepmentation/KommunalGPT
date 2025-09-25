# KommunalGPT Setup (Windows PowerShell)
# Requires PowerShell 5.1 or higher

param(
    [string]$GPTName = "",
    [string]$ResumeFromStep = ""
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Setup State Management
$StateFile = "setup-state.json"

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

# State Management Functions
function Save-SetupState {
    param(
        [string]$CurrentStep,
        [hashtable]$Data = @{}
    )
    
    $state = @{
        CurrentStep = $CurrentStep
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Data = $Data
    }
    
    $state | ConvertTo-Json | Set-Content $StateFile
    Write-Info "Setup-Status gespeichert: $CurrentStep"
}

function Get-SetupState {
    if (Test-Path $StateFile) {
        try {
            $state = Get-Content $StateFile | ConvertFrom-Json
            return @{
                CurrentStep = $state.CurrentStep
                Data = $state.Data
            }
        }
        catch {
            Write-Warning "Setup-Status konnte nicht gelesen werden. Starte von vorne."
            return $null
        }
    }
    return $null
}

function Clear-SetupState {
    if (Test-Path $StateFile) {
        Remove-Item $StateFile -Force
        Write-Info "Setup-Status geloescht"
    }
}

function Request-Reboot {
    param([string]$Reason, [string]$NextStep)
    
    Write-Warning $Reason
    Write-Info "Ein Neustart wird empfohlen, damit die Aenderungen wirksam werden."
    Write-Host ""
    
    $rebootChoice = Read-Host "Moechten Sie jetzt neu starten? Das Setup wird automatisch fortgesetzt. (J/n)"
    
    if ([string]::IsNullOrEmpty($rebootChoice) -or $rebootChoice -match "^[JjYy]") {
        # Status für Fortsetzung nach Reboot speichern
        Save-SetupState -CurrentStep $NextStep -Data @{
            GPTName = $script:GPTName
        }
        
        Write-Info "Setup wird nach dem Neustart automatisch fortgesetzt..."
        Write-Info "Fuehren Sie nach dem Neustart einfach 'setup.ps1' erneut aus."
        Write-Host ""
        Write-Warning "System wird in 10 Sekunden neu gestartet..."
        Start-Sleep -Seconds 10
        
        Restart-Computer -Force
        exit 0
    } else {
        Write-Info "Neustart uebersprungen. Setup wird fortgesetzt..."
        Write-Warning "Hinweis: Manche Funktionen koennten erst nach einem Neustart verfuegbar sein."
    }
}

function Initialize-DockerPath {
    # Prüfe ob Docker bereits verfügbar ist
    if (Test-CommandExists "docker") {
        return $true
    }
    
    # Übliche Docker-Installationspfade
    $dockerPaths = @(
        "${env:ProgramFiles}\Docker\Docker\resources\bin",
        "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin",
        "$env:USERPROFILE\AppData\Local\Programs\Docker\Docker\resources\bin",
        "${env:ProgramFiles}\Docker Desktop\resources\bin"
    )
    
    foreach ($path in $dockerPaths) {
        if (Test-Path "$path\docker.exe") {
            Write-Info "Docker gefunden in: $path"
            $env:PATH = "$path;$env:PATH"
            return $true
        }
    }
    
    return $false
}

function Test-DockerRunning {
    try {
        $null = docker version 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Start-DockerDesktop {
    Write-Info "Versuche Docker Desktop zu starten..."
    
    # Mögliche Docker Desktop Pfade
    $dockerDesktopPaths = @(
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Docker\Docker\Docker Desktop.exe"
    )
    
    foreach ($path in $dockerDesktopPaths) {
        if (Test-Path $path) {
            Write-Info "Starte Docker Desktop von: $path"
            Start-Process -FilePath $path -WindowStyle Hidden
            
            # Warte auf Docker Desktop Start
            Write-Info "Warte auf Docker Desktop Start (bis zu 60 Sekunden)..."
            $timeout = 60
            $elapsed = 0
            
            while ($elapsed -lt $timeout) {
                Start-Sleep -Seconds 5
                $elapsed += 5
                
                if (Test-DockerRunning) {
                    Write-Success "Docker Desktop erfolgreich gestartet"
                    return $true
                }
                
                Write-Host "." -NoNewline -ForegroundColor Yellow
            }
            
            Write-Host ""
            Write-Warning "Docker Desktop Start dauert länger als erwartet"
            return $false
        }
    }
    
    Write-Warning "Docker Desktop konnte nicht gefunden werden"
    return $false
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

    # Prüfe ob Setup fortgesetzt werden soll
    $savedState = Get-SetupState
    $startStep = "config"
    
    if ($savedState -and [string]::IsNullOrEmpty($ResumeFromStep)) {
        Write-Info "Vorheriger Setup-Status gefunden: $($savedState.CurrentStep)"
        $resumeChoice = Read-Host "Moechten Sie das Setup von diesem Punkt fortsetzen? (J/n)"
        
        if ([string]::IsNullOrEmpty($resumeChoice) -or $resumeChoice -match "^[JjYy]") {
            $startStep = $savedState.CurrentStep
            if ($savedState.Data.GPTName) {
                $GPTName = $savedState.Data.GPTName
            }
            Write-Success "Setup wird fortgesetzt ab: $startStep"
        } else {
            Clear-SetupState
            Write-Info "Setup wird von vorne gestartet"
        }
    } elseif (-not [string]::IsNullOrEmpty($ResumeFromStep)) {
        $startStep = $ResumeFromStep
        Write-Info "Setup wird fortgesetzt ab: $startStep"
    }

    # Setup Steps mit State Management
    $script:GPTName = $GPTName

    # 1) Name abfragen
    if ($startStep -eq "config") {
        Write-Title "Konfiguration"
        $defaultName = "KommunalGPT"
        
        if ([string]::IsNullOrEmpty($GPTName)) {
            $GPTName = Read-Host "Wie soll Ihr GPT heissen? [$defaultName]"
            if ([string]::IsNullOrEmpty($GPTName)) {
                $GPTName = $defaultName
            }
        }
        
        $script:GPTName = $GPTName
        Write-Success "Name gesetzt: $GPTName"
        Save-SetupState -CurrentStep "env" -Data @{ GPTName = $GPTName }
    }

    # 2) .env erstellen/aktualisieren
    if ($startStep -eq "config" -or $startStep -eq "env") {
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
        Save-SetupState -CurrentStep "docker" -Data @{ GPTName = $GPTName }
    }

    # 3) Docker pruefen/installieren
    if ($startStep -eq "config" -or $startStep -eq "env" -or $startStep -eq "docker") {
        Write-Title "Pruefe/Installiere Docker"
        
        # Versuche Docker-Pfad zu initialisieren
        if (-not (Initialize-DockerPath)) {
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
                        
                        # Reboot nach Docker-Installation anbieten
                        Request-Reboot -Reason "Docker Desktop wurde installiert." -NextStep "ollama"
                        
                        # Falls kein Reboot: Versuche Docker zu finden
                        Write-Info "Bitte Docker Desktop starten..."
                        Read-Host "Druecken Sie Enter, wenn Docker Desktop gestartet ist"
                        
                        if (-not (Initialize-DockerPath)) {
                            Write-Error "Docker konnte auch nach der Installation nicht gefunden werden."
                            Write-Info "Ein Neustart wird dringend empfohlen."
                            Request-Reboot -Reason "Docker ist nach Installation nicht verfuegbar." -NextStep "ollama"
                        }
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
                    Save-SetupState -CurrentStep "docker" -Data @{ GPTName = $GPTName }
                    exit 0
                }
            }
        } else {
            Write-Success "Docker wurde bereits auf dem System gefunden, Installation von Docker wird uebersprungen."
            $dockerVersion = docker --version
            Write-Success "Docker Version: $dockerVersion"
        }
        Save-SetupState -CurrentStep "ollama" -Data @{ GPTName = $GPTName }
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
    if ($startStep -eq "config" -or $startStep -eq "env" -or $startStep -eq "docker" -or $startStep -eq "ollama") {
        Write-Title "Pull Docker-Images"
        
        # Stelle sicher, dass Docker verfügbar und läuft
        if (-not (Initialize-DockerPath)) {
            Write-Error "Docker ist nicht verfuegbar. Bitte installieren Sie Docker Desktop und starten Sie das Setup erneut."
            exit 1
        }
        
        if (-not (Test-DockerRunning)) {
            Write-Warning "Docker Desktop laeuft nicht. Versuche zu starten..."
            
            if (-not (Start-DockerDesktop)) {
                Write-Error "Docker Desktop konnte nicht gestartet werden."
                Write-Info "Bitte starten Sie Docker Desktop manuell und führen Sie das Setup erneut aus."
                Write-Info "Alternativ können Sie das System neu starten."
                exit 1
            }
        } else {
            Write-Success "Docker Desktop läuft bereits"
        }
        
        try {
            Write-Info "Lade Docker Images... (Dies kann einige Minuten dauern)"
            $pullResult = docker compose pull 2>&1
            
            # Prüfe auf Fehler in der Ausgabe
            if ($LASTEXITCODE -ne 0 -or $pullResult -match "error|Error|ERROR") {
                Write-Warning "Warnung beim Laden der Docker Images:"
                Write-Host $pullResult -ForegroundColor Yellow
                Write-Info "Versuche trotzdem fortzufahren..."
            } else {
                Write-Success "Docker Images erfolgreich geladen"
            }
        }
        catch {
            Write-Error "Fehler beim Laden der Docker Images: $($_.Exception.Message)"
            Write-Info "Stellen Sie sicher, dass Docker Desktop gestartet ist und Sie mit dem Internet verbunden sind."
            Write-Info "Versuche trotzdem fortzufahren..."
        }
        Save-SetupState -CurrentStep "init" -Data @{ GPTName = $GPTName }
    }

    # 6) Initialstart nur Frontend
    if ($startStep -eq "config" -or $startStep -eq "env" -or $startStep -eq "docker" -or $startStep -eq "ollama" -or $startStep -eq "init") {
        Write-Title "Initialer Start (Ressourcen anlegen)"
        
        # Stelle sicher, dass Docker läuft
        if (-not (Test-DockerRunning)) {
            Write-Warning "Docker Desktop läuft nicht. Versuche zu starten..."
            if (-not (Start-DockerDesktop)) {
                Write-Error "Docker Desktop konnte nicht gestartet werden."
                Write-Info "Bitte starten Sie Docker Desktop manuell und führen Sie das Setup erneut aus."
                exit 1
            }
        }
        
        try {
            Write-Info "Starte KommunalGPT Container..."
            $startResult = docker compose up -d kommunal-gpt 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Warnung beim Starten des Containers:"
                Write-Host $startResult -ForegroundColor Yellow
            } else {
                Write-Success "Container erfolgreich gestartet"
            }
            
            Write-Info "Warte 25 Sekunden auf Initialisierung..."
            Start-Sleep -Seconds 25
            
            Write-Info "Stoppe Container..."
            docker compose down | Out-Null
            Write-Success "Initiale Ressourcen erfolgreich angelegt"
        }
        catch {
            Write-Error "Fehler beim initialen Start: $($_.Exception.Message)"
            Write-Info "Versuche trotzdem fortzufahren..."
        }
        Save-SetupState -CurrentStep "files" -Data @{ GPTName = $GPTName }
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
    
    # Stelle sicher, dass Docker läuft
    if (-not (Test-DockerRunning)) {
        Write-Warning "Docker Desktop läuft nicht. Versuche zu starten..."
        if (-not (Start-DockerDesktop)) {
            Write-Error "Docker Desktop konnte nicht gestartet werden."
            Write-Info "Bitte starten Sie Docker Desktop manuell und führen Sie das Setup erneut aus."
            exit 1
        }
    }
    
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
    
    # Setup-Status löschen da erfolgreich abgeschlossen
    Clear-SetupState
    
    Write-Host ""
    Write-Info "Sie finden das KommunalGPT-Dashboard im Browser unter http://localhost"
    Write-Host ""
    Write-Info "compAInion/Open WebUI selbst laeuft auf Port 3000 dieses Servers"
    Write-Info "bitte loggen Sie sich im Browser unter http://localhost:3000"
    Write-Info "zur Administration mit folgenden Daten ein:"
    Write-Host ""
    Write-Success "E-Mail: info@KommunalGPT.de"
    Write-Success "Passwort: CompAdmin#2025!"

}
catch {
    Write-Error "Fehler beim Ausfuehren des Setups: $($_.Exception.Message)"
    Write-Host "Bitte ueberpruefen Sie die Ausgabe und versuchen Sie es erneut." -ForegroundColor Red
    Write-Info "Der Setup-Status wurde gespeichert. Sie koennen das Setup spaeter fortsetzen."
    exit 1
}
