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

# Port-Prüfungs-Funktionen
function Test-PortInUse {
    param([int]$Port)
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        return ($connections.Count -gt 0)
    }
    catch {
        # Fallback für ältere PowerShell-Versionen
        try {
            $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
            $listener.Start()
            $listener.Stop()
            return $false
        }
        catch {
            return $true
        }
    }
}

function Get-AlternativePort {
    param(
        [string]$ServiceName,
        [int]$SuggestedPort
    )
    
    while ($true) {
        $newPort = Read-Host "Port fuer $ServiceName [Vorschlag: $SuggestedPort]"
        if ([string]::IsNullOrEmpty($newPort)) {
            $newPort = $SuggestedPort
        }
        
        try {
            $portNum = [int]$newPort
            if ($portNum -lt 1 -or $portNum -gt 65535) {
                Write-Warning "Ungueltiger Port. Bitte eine Zahl zwischen 1 und 65535 eingeben."
                continue
            }
            
            if (Test-PortInUse -Port $portNum) {
                Write-Warning "Port $portNum ist bereits belegt. Bitte einen anderen Port waehlen."
                continue
            }
            
            # Prüfe ob Port bereits von einem anderen Service reserviert wurde
            if ($portNum -eq $script:OllamaPort -or $portNum -eq $script:WebuiPort -or `
                $portNum -eq $script:TikaPort -or $portNum -eq $script:CompainionUiPort) {
                Write-Warning "Port $portNum wird bereits von einem anderen Service verwendet. Bitte einen anderen Port waehlen."
                continue
            }
            
            return $portNum
        }
        catch {
            Write-Warning "Ungueltige Eingabe. Bitte eine gueltige Portnummer eingeben."
        }
    }
}

# .env-Hilfsfunktionen
# Schreibt immer in die .env, nie in die versionierte Vorlage .env.example.
function Set-EnvValue {
    param([string]$Key, [string]$Value)
    if (-not (Test-Path ".env")) { New-Item -Path ".env" -ItemType File | Out-Null }
    $lines = @(Get-Content ".env")
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^$([regex]::Escape($Key))=") {
            $lines[$i] = "$Key=$Value"
            $found = $true
        }
    }
    if (-not $found) { $lines += "$Key=$Value" }
    $lines | Set-Content ".env"
}

function Get-EnvValue {
    param([string]$Key, [string]$File = ".env")
    if (-not (Test-Path $File)) { return "" }
    $line = Get-Content $File | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return ($line -replace "^$([regex]::Escape($Key))=", "").Trim("'", '"')
}

# Liest die Ports aus der .env in die Script-Variablen (mit Standardwerten).
# Wird auch beim Fortsetzen eines unterbrochenen Setups benoetigt.
function Import-PortsFromEnv {
    $p = Get-EnvValue "OLLAMA_PORT";        $script:OllamaPort       = if ($p) { [int]$p } else { 11434 }
    $p = Get-EnvValue "WEBUI_PORT";         $script:WebuiPort        = if ($p) { [int]$p } else { 3000 }
    $p = Get-EnvValue "TIKA_PORT";          $script:TikaPort         = if ($p) { [int]$p } else { 9998 }
    $p = Get-EnvValue "COMPAINION_UI_PORT"; $script:CompainionUiPort = if ($p) { [int]$p } else { 8080 }
}

# Prueft, ob ein lokal laufendes Ollama aus einem Docker-Container erreichbar ist.
# Open WebUI spricht Ollama als http://host.docker.internal:11434 an. Lauscht Ollama nur auf
# 127.0.0.1, sieht Open WebUI keine Modelle - das faellt sonst erst dem ersten Nutzer auf.
function Test-OllamaFromContainer {
    param([int]$Port = 11434)
    $null = docker run --rm --add-host=host.docker.internal:host-gateway curlimages/curl:latest -s --max-time 10 "http://host.docker.internal:$Port/api/version" 2>$null
    return ($LASTEXITCODE -eq 0)
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
        Save-SetupState -CurrentStep "ports" -Data @{ GPTName = $GPTName }
    }

    # 2) Port-Prüfung und Konfiguration
    if ($startStep -eq "config" -or $startStep -eq "ports") {
        Write-Title "Pruefe Ports"
        
        # .env anlegen, bevor Ports geprueft werden - die Ports landen direkt dort
        if (-not (Test-Path ".env")) {
            if (Test-Path ".env.example") {
                Copy-Item ".env.example" ".env"
                Write-Success ".env aus .env.example erstellt"
            } else {
                New-Item -Path ".env" -ItemType File | Out-Null
                Write-Warning ".env.example nicht gefunden - leere .env angelegt"
            }
        } else {
            Write-Success "Bestehende .env wird weiterverwendet"
        }

        # Aktuelle Ports aus der .env lesen (nicht aus der Vorlage .env.example)
        Import-PortsFromEnv

        # Prüfe jeden Port
        $portsChanged = $false
        
        # Spezielle Prüfung für Ollama-Port
        if (Test-PortInUse -Port $OllamaPort) {
            # Port ist belegt - prüfe ob es Ollama ist
            try {
                $response = Invoke-RestMethod -Uri "http://localhost:$OllamaPort/api/version" -Method Get -TimeoutSec 5 -ErrorAction Stop
                Write-Success "Port $OllamaPort ist von Ollama belegt - wird verwendet"
            }
            catch {
                # Open WebUI spricht Ollama laut mitgelieferter Datenbank fest ueber Port 11434 an.
                # Ein Ausweichen auf einen anderen Port wuerde die Anbindung lautlos zerstoeren.
                Write-Warning "Port $OllamaPort wird von einem anderen Dienst belegt - nicht von Ollama."
                Write-Warning "KommunalGPT benoetigt diesen Port zwingend fuer die Ollama-Anbindung."
                Write-Warning "Bitte geben Sie Port $OllamaPort frei und starten Sie das Setup erneut."
                exit 1
            }
        } else {
            Write-Success "Port $OllamaPort (Ollama) ist frei"
        }
        
        if (Test-PortInUse -Port $WebuiPort) {
            Write-Warning "Port $WebuiPort (Open WebUI) ist bereits belegt!"
            $script:WebuiPort = Get-AlternativePort -ServiceName "Open WebUI" -SuggestedPort 3001
            $portsChanged = $true
            Write-Success "Neuer Open WebUI-Port: $WebuiPort"
        } else {
            Write-Success "Port $WebuiPort (Open WebUI) ist frei"
        }
        
        if (Test-PortInUse -Port $TikaPort) {
            Write-Warning "Port $TikaPort (Tika) ist bereits belegt!"
            $script:TikaPort = Get-AlternativePort -ServiceName "Tika" -SuggestedPort 9999
            $portsChanged = $true
            Write-Success "Neuer Tika-Port: $TikaPort"
        } else {
            Write-Success "Port $TikaPort (Tika) ist frei"
        }
        
        if (Test-PortInUse -Port $CompainionUiPort) {
            Write-Warning "Port $CompainionUiPort (KommunalGPT-Dashboard) ist bereits belegt!"
            $script:CompainionUiPort = Get-AlternativePort -ServiceName "KommunalGPT-Dashboard" -SuggestedPort 8080
            $portsChanged = $true
            Write-Success "Neuer KommunalGPT-Dashboard-Port: $CompainionUiPort"
        } else {
            Write-Success "Port $CompainionUiPort (KommunalGPT-Dashboard) ist frei"
        }
        
        # Ports in die .env schreiben (NICHT in die versionierte Vorlage .env.example)
        if ($portsChanged) { Write-Info "Uebernehme neue Ports in die .env..." }
        Set-EnvValue "OLLAMA_PORT" $OllamaPort
        Set-EnvValue "WEBUI_PORT" $WebuiPort
        Set-EnvValue "TIKA_PORT" $TikaPort
        Set-EnvValue "COMPAINION_UI_PORT" $CompainionUiPort

        Save-SetupState -CurrentStep "env" -Data @{ 
            GPTName = $GPTName
            OllamaPort = $OllamaPort
            WebuiPort = $WebuiPort
            TikaPort = $TikaPort
            CompainionUiPort = $CompainionUiPort
        }
    }

    # 3) .env erstellen/aktualisieren
    if ($startStep -eq "config" -or $startStep -eq "ports" -or $startStep -eq "env") {
        Write-Title "Konfiguriere .env"
        
        if (-not (Test-Path ".env")) {
            if (Test-Path ".env.example") {
                Copy-Item ".env.example" ".env"
            } else {
                New-Item -Path ".env" -ItemType File | Out-Null
            }
        }
        Import-PortsFromEnv

        Set-EnvValue "COMPAINION_NAME" "'$GPTName'"

        # Dashboard-Weiterleitung auf den tatsaechlichen Host setzen, damit der Link auch von
        # Arbeitsplatz-Rechnern funktioniert und nicht auf deren eigenen "localhost" zeigt.
        $defaultHost = "localhost"
        try {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.InterfaceAlias -notmatch "Loopback|vEthernet|WSL|Docker" -and $_.IPAddress -notmatch "^169\.254\." } |
                Select-Object -First 1 -ExpandProperty IPAddress
            if ($ip) { $defaultHost = $ip }
        } catch { }
        $serverHost = Read-Host "Unter welchem Hostnamen/IP ist dieser Server erreichbar? [$defaultHost]"
        if ([string]::IsNullOrEmpty($serverHost)) { $serverHost = $defaultHost }
        Set-EnvValue "SERVER_HOST" $serverHost
        Set-EnvValue "COMPAINION_DEFAULT_URL" ('"http://' + $serverHost + ':${WEBUI_PORT}"')
        Write-Success "Dashboard verweist auf http://${serverHost}:$WebuiPort"

        Write-Success ".env aktualisiert"
        Save-SetupState -CurrentStep "docker" -Data @{ GPTName = $GPTName }
    }

    # 4) Docker pruefen/installieren
    if ($startStep -eq "config" -or $startStep -eq "ports" -or $startStep -eq "env" -or $startStep -eq "docker") {
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

    # 5) Ollama pruefen
    Write-Title "Pruefe Ollama"
    
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
        } else {
            Write-Success "Hinweis: Das bereits als Docker-Container laufende Ollama wird verwendet."
            Write-Success "Modelle werden in den Container geladen."
        }
    } else {
        Write-Success "Modelle werden nach dem Start in den Container geladen."
    }

    # Ollama-Container per Compose-Profil zu- oder abschalten.
    # Frueher wurde die Ollama-Sektion ueber feste Zeilennummern auskommentiert - das zerbrach bei
    # jeder Aenderung am Dateikopf. Das Profil "ollama" ist unabhaengig vom Dateiaufbau.
    if ($ollamaType -eq "local") {
        Set-EnvValue "COMPOSE_PROFILES" ""
        Write-Success "Lokales Ollama wird verwendet - der Ollama-Container bleibt ausgeschaltet."
    } else {
        Set-EnvValue "COMPOSE_PROFILES" "ollama"
        Write-Success "Ollama wird als Container bereitgestellt (Compose-Profil 'ollama' aktiv)."
    }

    # 6) Pull Images
    if ($startStep -eq "config" -or $startStep -eq "ports" -or $startStep -eq "env" -or $startStep -eq "docker" -or $startStep -eq "ollama") {
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
            Write-Success "Docker Desktop laeuft bereits"
        }
        
        try {
            Write-Info "Lade Docker Images... (Dies kann einige Minuten dauern)"
            Write-Host ""
            
            # Führe docker compose pull direkt aus, um Live-Fortschritt zu sehen
            docker compose pull
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host ""
                Write-Warning "Warnung beim Laden der Docker Images (Exit Code: $LASTEXITCODE)"
                Write-Info "Versuche trotzdem fortzufahren..."
            } else {
                Write-Host ""
                Write-Success "Docker Images erfolgreich geladen"
            }
        }
        catch {
            Write-Host ""
            Write-Error "Fehler beim Laden der Docker Images: $($_.Exception.Message)"
            Write-Info "Stellen Sie sicher, dass Docker Desktop gestartet ist und Sie mit dem Internet verbunden sind."
            Write-Info "Versuche trotzdem fortzufahren..."
        }
        Save-SetupState -CurrentStep "init" -Data @{ GPTName = $GPTName }
    }

    # 7) Initialstart nur Frontend
    if ($startStep -eq "config" -or $startStep -eq "ports" -or $startStep -eq "env" -or $startStep -eq "docker" -or $startStep -eq "ollama" -or $startStep -eq "init") {
        Write-Title "Initialer Start (Ressourcen anlegen)"
        
        # Stelle sicher, dass Docker läuft
        if (-not (Test-DockerRunning)) {
            Write-Warning "Docker Desktop laeuft nicht. Versuche zu starten..."
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

    # 8) Standard-Datenbank einsetzen
    # Hinweis: Das Branding von Open WebUI wird bewusst NICHT mehr ueberschrieben. Frueher wurde
    # static\* nach owui\static\ kopiert - das ersetzte Favicon und Splash von Open WebUI und stand
    # im Konflikt mit dessen Branding-Klausel. Der Name bleibt ueber WEBUI_NAME erhalten.
    Write-Title "Standard-Datenbank einsetzen"

    if (-not (Test-Path "owui\data")) {
        New-Item -Path "owui\data" -ItemType Directory -Force | Out-Null
    }

    if (Test-Path "master-webui.db") {
        try {
            # WAL-Dateien des initialen Starts entfernen. Open WebUI arbeitet im SQLite-WAL-Modus und
            # hinterlaesst beim Stoppen webui.db-wal/-shm. Bleiben sie neben der eingespielten
            # Master-DB liegen, spielt SQLite sie ein -> "database disk image is malformed".
            Remove-Item "owui\data\webui.db-wal", "owui\data\webui.db-shm" -Force -ErrorAction SilentlyContinue
            Copy-Item "master-webui.db" "owui\data\webui.db" -Force -ErrorAction Stop
            Write-Success "DB eingesetzt: owui\data\webui.db"
        }
        catch {
            Write-Error "Die Standard-Datenbank konnte nicht eingesetzt werden: $($_.Exception.Message)"
            Write-Info "Open WebUI wuerde ohne die vorkonfigurierten Assistenten starten. Setup abgebrochen."
            exit 1
        }
    } else {
        Write-Warning "master-webui.db nicht gefunden - uebersprungen."
    }

    # 9) System starten
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
    
    # Lokales Ollama muss aus dem Container erreichbar sein
    if ($ollamaType -eq "local") {
        Write-Info "Pruefe Ollama-Erreichbarkeit aus dem Container..."
        if (Test-OllamaFromContainer) {
            Write-Success "Ollama ist aus dem Container erreichbar"
        } else {
            Write-Warning "Ollama laeuft lokal, ist aus dem Docker-Container aber NICHT erreichbar."
            Write-Warning "Open WebUI wuerde dadurch ohne Modelle starten."
            Write-Host ""
            Write-Host "Ursache: Ollama lauscht vermutlich nur auf 127.0.0.1."
            Write-Host "Abhilfe: Umgebungsvariable setzen und Ollama neu starten:"
            Write-Host '  [Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", "User")'
            Write-Host ""
            $continueAnyway = Read-Host "Trotzdem fortfahren? (j/N)"
            if ($continueAnyway -notmatch "^[JjYy]") {
                Write-Info "Setup abgebrochen. Bitte Ollama erreichbar machen und erneut starten."
                exit 1
            }
        }
    }

    try {
        if ($ollamaType -eq "local") {
            Write-Info "Starte System (ohne Ollama-Container, da lokal installiert)..."
        } else {
            Write-Info "Starte System mit Ollama-Container..."
        }
        docker compose up -d
        Write-Success "System erfolgreich gestartet"
    }
    catch {
        Write-Error "Fehler beim Starten des Systems"
        throw
    }

    # 10) Optional: Modelle laden
    Write-Title "Modelle laden"
    Write-Host "Die Sprachmodelle koennen jetzt geladen werden. Das sind je nach Auswahl mehrere"
    Write-Host "Gigabyte und kann eine Weile dauern. Sie koennen das auch spaeter mit .\models.ps1 nachholen."

    $loadModels = Read-Host "Modelle jetzt laden? (j/N)"
    if ($loadModels -match "^[JjYy]") {
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
    } else {
        Write-Info "Modelle uebersprungen. Nachholen jederzeit mit: .\models.ps1"
    }

    # Setup abgeschlossen
    Write-Title "Setup abgeschlossen"
    Write-Success "Setup erfolgreich abgeschlossen!"
    
    # Setup-Status löschen da erfolgreich abgeschlossen
    Clear-SetupState
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  KommunalGPT ist bereit!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Import-PortsFromEnv
    $serverHost = Get-EnvValue "SERVER_HOST"
    if (-not $serverHost) { $serverHost = "localhost" }
    Write-Host "[Dashboard] KommunalGPT-Dashboard (Startseite fuer Nutzer):" -ForegroundColor Yellow
    Write-Host "   http://${serverHost}:$CompainionUiPort" -ForegroundColor White
    Write-Host ""
    Write-Host "[Einstellungen] KommunalGPT-Dashboard:" -ForegroundColor Yellow
    Write-Host "   Admin-Token: siehe COMPAINION_UI_ADMIN_TOKEN in der Datei .env" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[Administration] Open WebUI:" -ForegroundColor Yellow
    Write-Host "   http://${serverHost}:$WebuiPort" -ForegroundColor White
    Write-Host "   E-Mail: info@KommunalGPT.de" -ForegroundColor Gray
    Write-Host ""
    Write-Host "WICHTIG: Melden Sie sich jetzt an und aendern Sie das Administrator-Passwort." -ForegroundColor Red
    Write-Host "   Das Auslieferungspasswort ist oeffentlich dokumentiert und auf jeder Installation" -ForegroundColor Red
    Write-Host "   identisch. Solange es gilt, ist Ihre Installation nicht geschuetzt." -ForegroundColor Red
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan

}
catch {
    Write-Error "Fehler beim Ausfuehren des Setups: $($_.Exception.Message)"
    Write-Host "Bitte ueberpruefen Sie die Ausgabe und versuchen Sie es erneut." -ForegroundColor Red
    Write-Info "Der Setup-Status wurde gespeichert. Sie koennen das Setup spaeter fortsetzen."
    exit 1
}
