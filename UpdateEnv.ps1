param(
    [string]$Name = (Get-Content env.txt -Raw).Trim()
)

$path = '.env'
if (!(Test-Path $path)) { New-Item -ItemType File -Path $path }

$content = Get-Content $path

$content = if ($content -match '^COMPAINION_NAME=') {
              $content -replace '^COMPAINION_NAME=.*', "COMPAINION_NAME='$Name'"
           } else {
              $content + "`nCOMPAINION_NAME='$Name'"
           }

$content = if ($content -match '^OLLAMA_BASE_URL=') {
              $content -replace '^OLLAMA_BASE_URL=.*', "OLLAMA_BASE_URL='http://localhost:11434'"
           } else {
              $content + "`nOLLAMA_BASE_URL='http://localhost:11434'"
           }

Set-Content -NoNewline -Path $path -Value $content
