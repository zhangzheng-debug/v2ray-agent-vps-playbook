[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$Domain,

    [string]$ProfileToken = $env:PROFILE_TOKEN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProfileToken)) {
    throw 'Set PROFILE_TOKEN in the process environment or pass -ProfileToken. The token is never printed.'
}

Add-Type -AssemblyName System.Net.Http
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $true
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(30)

function Test-SubscriptionEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $uri = [Uri]::new("https://$Domain$Path")
    $response = $client.GetAsync($uri).GetAwaiter().GetResult()
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $contentType = if ($response.Content.Headers.ContentType) {
        $response.Content.Headers.ContentType.ToString()
    } else {
        'unknown'
    }

    $mitigated = $false
    $values = $null
    if ($response.Headers.TryGetValues('Cf-Mitigated', [ref]$values)) {
        $mitigated = ($values -contains 'challenge')
    }

    $isHtml = $body -match '(?i)<!doctype html|<html'
    $hasYamlMarker = $body -match '(?m)^(proxies|proxy-groups|mixed-port|port):'

    [pscustomobject]@{
        Endpoint       = $Label
        Status         = [int]$response.StatusCode
        ContentType    = $contentType
        Bytes          = [Text.Encoding]::UTF8.GetByteCount($body)
        Challenge      = $mitigated
        LooksLikeHtml  = $isHtml
        HasYamlMarkers = $hasYamlMarker
        Passed         = $response.IsSuccessStatusCode -and -not $mitigated -and -not $isHtml -and $hasYamlMarker
    }
}

try {
    Write-Host "domain=$Domain"
    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
        $a = @(Resolve-DnsName -Name $Domain -Type A -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress)
        $aaaa = @(Resolve-DnsName -Name $Domain -Type AAAA -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress)
        Write-Host "A=$($a -join ',')"
        Write-Host "AAAA=$($aaaa -join ',')"
    }

    $results = @(
        Test-SubscriptionEndpoint -Label 'profile' -Path "/s/clashMetaProfiles/$ProfileToken"
        Test-SubscriptionEndpoint -Label 'provider' -Path "/s/clashMeta/$ProfileToken"
    )
    $results | Format-Table -AutoSize

    if ($results.Where({ -not $_.Passed }).Count -gt 0) {
        throw 'Endpoint validation failed. Check HTTP status, Cloudflare challenge, and YAML markers.'
    }

    Write-Host 'endpoint_validation=passed'
} finally {
    $client.Dispose()
    $handler.Dispose()
}
