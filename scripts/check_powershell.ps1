# Prueft PowerShell-Skripte auf Parse-Fehler - so, wie PowerShell 7 (UTF-8) und Windows
# PowerShell 5.1 (liest Dateien ohne BOM als Windows-1252) sie lesen.
param([string[]]$Files = @("setup.ps1", "models.ps1"))
[Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
$failed = 0
foreach ($file in $Files) {
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path $file))
    foreach ($enc in @(@{ Name = "PowerShell 7 (UTF-8)"; E = [Text.Encoding]::UTF8 },
                       @{ Name = "Windows PowerShell 5.1 (Windows-1252)"; E = [Text.Encoding]::GetEncoding(1252) })) {
        $errs = $null; $tok = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($enc.E.GetString($bytes), [ref]$tok, [ref]$errs)
        if ($errs.Count -eq 0) { Write-Host "OK    $file - $($enc.Name)" }
        else {
            $failed++
            Write-Host "FEHLER $file - $($enc.Name): $($errs.Count) Parse-Fehler"
            $errs | Select-Object -First 5 | ForEach-Object { Write-Host "   Zeile $($_.Extent.StartLineNumber): $($_.Message)" }
        }
    }
}
exit $failed
