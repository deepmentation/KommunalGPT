param(
    [Parameter(Mandatory=$true)]
    [string]$Name
)

# Falls .env nicht existiert, erstellen
if (-not (Test-Path '.env')) {
    New-Item -ItemType File -Path '.env' | Out-Null
}

Add-Content -Path '.env' -Value "COMPAINION_NAME='$Name'"
