[CmdletBinding()]
param(
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)

$excludedDirectories = @('.git', 'evidence', 'backups', 'tmp')
$textExtensions = @('.md', '.txt', '.ps1', '.sh', '.yaml', '.yml', '.json', '.conf', '.example', '.gitignore')
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param([string]$File, [int]$Line, [string]$Reason)
    $findings.Add([pscustomobject]@{ File = $File; Line = $Line; Reason = $Reason })
}

function Test-AllowedIpv4 {
    param([string]$Address)
    return $Address -match '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' -or
        $Address -match '^(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)' -or
        $Address -in @('0.0.0.0', '1.1.1.1', '8.8.8.8')
}

$files = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
    $relativeParts = $_.FullName.Substring($Root.Length).TrimStart('\', '/').Split([IO.Path]::DirectorySeparatorChar)
    -not ($relativeParts | Where-Object { $_ -in $excludedDirectories }) -and
    ($_.Name -eq '.gitignore' -or $_.Extension -in $textExtensions)
}

foreach ($file in $files) {
    $relative = $file.FullName.Substring($Root.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadLines($file.FullName)) {
        $lineNumber++

        if ($line -match '-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----') {
            Add-Finding $relative $lineNumber 'private key material'
        }

        foreach ($match in [regex]::Matches($line, '(?<![A-Fa-f0-9])(?:\d{1,3}\.){3}\d{1,3}(?![A-Fa-f0-9])')) {
            if (-not (Test-AllowedIpv4 $match.Value)) {
                Add-Finding $relative $lineNumber 'non-documentation IPv4 address'
            }
        }

        foreach ($match in [regex]::Matches($line, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b')) {
            if ($match.Value -notmatch '(?i)@example\.com$|@users\.noreply\.github\.com$') {
                Add-Finding $relative $lineNumber 'email address'
            }
        }

        if ($line -match '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b') {
            Add-Finding $relative $lineNumber 'UUID-like secret'
        }

        if ($line -match '(?i)(api[_ -]?token|private[_ -]?key|profile[_ -]?token|password)\s*[:=]\s*["'']?(?!<|REPLACE|$)[A-Za-z0-9_./+=-]{20,}') {
            Add-Finding $relative $lineNumber 'assigned long credential-like value'
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object File, Line, Reason | Format-Table -AutoSize
    throw "Secret scan failed with $($findings.Count) finding(s)."
}

Write-Host "secret_scan=passed files=$($files.Count)"
