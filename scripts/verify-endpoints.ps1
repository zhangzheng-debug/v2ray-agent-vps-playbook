[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$Domain,

    [string]$ProfileToken = $env:PROFILE_TOKEN,

    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$EdgeDomain,

    [ValidatePattern('^[A-Za-z0-9.:-]+$')]
    [string]$DirectHost,

    [ValidateRange(1, 1000)]
    [int]$MinimumNodeCount = 2,

    [switch]$AllowIpv6Profile,

    [string]$ProfilePath,

    [string]$ProviderPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($EdgeDomain)) {
    $EdgeDomain = $Domain
}

$usingLocalFiles = -not [string]::IsNullOrWhiteSpace($ProfilePath) -or
    -not [string]::IsNullOrWhiteSpace($ProviderPath)
if ($usingLocalFiles -and
    ([string]::IsNullOrWhiteSpace($ProfilePath) -or [string]::IsNullOrWhiteSpace($ProviderPath))) {
    throw 'Pass both -ProfilePath and -ProviderPath when validating local fixtures.'
}
if (-not $usingLocalFiles -and [string]::IsNullOrWhiteSpace($ProfileToken)) {
    throw 'Set PROFILE_TOKEN in the process environment or pass -ProfileToken. The token is never printed.'
}

Add-Type -AssemblyName System.Net.Http
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $true
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(30)

function Get-EndpointResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('profile', 'provider')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$LocalPath
    )

    if (-not [string]::IsNullOrWhiteSpace($LocalPath)) {
        $resolved = (Resolve-Path -LiteralPath $LocalPath).Path
        $body = [IO.File]::ReadAllText($resolved)
        $status = 200
        $contentType = 'text/yaml; local-fixture'
        $mitigated = $false
        $success = $true
    } else {
        $uri = [Uri]::new("https://$Domain$Path")
        $response = $client.GetAsync($uri).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $status = [int]$response.StatusCode
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
        $success = $response.IsSuccessStatusCode
        $response.Dispose()
    }

    $isHtml = $body -match '(?i)<!doctype html|<html'
    $hasProxies = $body -match '(?m)^proxies\s*:'
    $hasProxyProviders = $body -match '(?m)^proxy-providers\s*:'
    $hasProxyGroups = $body -match '(?m)^proxy-groups\s*:'
    $hasRules = $body -match '(?m)^rules\s*:'
    $hasRuleMode = $body -match '(?m)^mode\s*:\s*rule\s*$'
    $ipv6Enabled = $body -match '(?m)^ipv6\s*:\s*true\s*$'

    $shapeOk = if ($Kind -eq 'profile') {
        ($hasProxies -or $hasProxyProviders) -and $hasProxyGroups -and $hasRules -and $hasRuleMode
    } else {
        $hasProxies -and -not $hasProxyGroups -and -not $hasRules
    }
    $ipv6Ok = $Kind -ne 'profile' -or $AllowIpv6Profile -or -not $ipv6Enabled

    [pscustomobject]@{
        Endpoint       = $Kind
        Status         = $status
        ContentType    = $contentType
        Bytes          = [Text.Encoding]::UTF8.GetByteCount($body)
        Challenge      = $mitigated
        LooksLikeHtml  = $isHtml
        Shape          = if ($shapeOk) { 'expected' } else { 'wrong' }
        Ipv6Profile    = $ipv6Enabled
        Passed         = $success -and -not $mitigated -and -not $isHtml -and $shapeOk -and $ipv6Ok
        Body           = $body
    }
}

function Get-ProxyAudit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    $matches = [regex]::Matches(
        $Body,
        '(?ms)^\s{2}- name:\s*(?<name>[^\r\n]+)\r?\n(?<body>.*?)(?=^\s{2}- name:|\z)'
    )
    $items = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($match in $matches) {
        $index++
        $block = $match.Value
        $serverMatch = [regex]::Match($block, '(?m)^\s+server:\s*["'']?(?<value>[^\s"'']+)')
        $portMatch = [regex]::Match($block, '(?m)^\s+port:\s*(?<value>\d+)')
        $networkMatch = [regex]::Match($block, '(?m)^\s+network:\s*(?<value>[^\s]+)')
        $server = if ($serverMatch.Success) { $serverMatch.Groups['value'].Value } else { '' }
        $port = if ($portMatch.Success) { [int]$portMatch.Groups['value'].Value } else { 0 }
        $network = if ($networkMatch.Success) { $networkMatch.Groups['value'].Value.ToLowerInvariant() } else { 'tcp' }
        $isReality = $block -match '(?m)^\s+reality-opts\s*:'
        $isWs = $network -eq 'ws'
        $isXhttp = $network -eq 'xhttp'
        $parsedAddress = $null
        $isIpAddress = [Net.IPAddress]::TryParse($server, [ref]$parsedAddress)
        $serverRole = if ($server -ieq $EdgeDomain) {
            'edge'
        } elseif (-not [string]::IsNullOrWhiteSpace($DirectHost) -and $server -ieq $DirectHost) {
            'direct'
        } elseif ($isIpAddress) {
            'ip'
        } else {
            'other'
        }

        $cloudflareHttpsPorts = @(443, 2053, 2083, 2087, 2096, 8443)
        $edgeRawPort = $serverRole -eq 'edge' -and $port -notin $cloudflareHttpsPorts
        $realityOnEdge = $isReality -and $serverRole -eq 'edge'
        $directMismatch = $isReality -and -not [string]::IsNullOrWhiteSpace($DirectHost) -and
            $server -ine $DirectHost

        $items.Add([pscustomobject]@{
            Node             = "#$index"
            Network          = $network
            Port             = $port
            ServerRole       = $serverRole
            Reality          = $isReality
            Ws               = $isWs
            Xhttp            = $isXhttp
            EdgeRawPort      = $edgeRawPort
            RealityOnEdge    = $realityOnEdge
            DirectMismatch   = $directMismatch
            Passed           = -not ($edgeRawPort -or $realityOnEdge -or $directMismatch)
        })
    }
    return $items
}

try {
    Write-Host "domain=$Domain"
    if (-not $usingLocalFiles -and (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
        $a = @(Resolve-DnsName -Name $Domain -Type A -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress)
        $aaaa = @(Resolve-DnsName -Name $Domain -Type AAAA -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress)
        Write-Host "A=$($a -join ',')"
        Write-Host "AAAA=$($aaaa -join ',')"
    }

    $profile = Get-EndpointResult -Kind profile -Path "/s/clashMetaProfiles/$ProfileToken" -LocalPath $ProfilePath
    $provider = Get-EndpointResult -Kind provider -Path "/s/clashMeta/$ProfileToken" -LocalPath $ProviderPath
    @($profile, $provider) |
        Select-Object Endpoint, Status, ContentType, Bytes, Challenge, LooksLikeHtml, Shape, Ipv6Profile, Passed |
        Format-Table -AutoSize

    if (-not $profile.Passed) {
        throw 'Full profile validation failed. It must be rule mode and contain proxy groups plus rules; provider-only YAML is not a full profile.'
    }
    if (-not $provider.Passed) {
        throw 'Provider validation failed. It must contain proxies and must not be mistaken for a full rule profile.'
    }

    $nodeAudit = @(Get-ProxyAudit -Body $provider.Body)
    $nodeAudit |
        Select-Object Node, Network, Port, ServerRole, Reality, Ws, Xhttp, EdgeRawPort, RealityOnEdge, DirectMismatch, Passed |
        Format-Table -AutoSize

    if ($nodeAudit.Count -lt $MinimumNodeCount) {
        throw "Provider has $($nodeAudit.Count) node(s); expected at least $MinimumNodeCount."
    }
    if ($nodeAudit.Where({ $_.Reality }).Count -eq 0) {
        throw 'Provider does not contain a Reality node.'
    }
    if ($nodeAudit.Where({ $_.Ws }).Count -eq 0) {
        throw 'Provider does not contain a WebSocket node.'
    }
    if ($nodeAudit.Where({ -not $_.Passed }).Count -gt 0) {
        throw 'Node routing audit failed. A proxied edge hostname is used by a Reality/raw-port node, or a direct host does not match the deployment contract.'
    }

    Write-Host 'endpoint_validation=passed'
    Write-Host 'subscription_shape=profile_rule_mode_provider_proxy_list'
    Write-Host 'node_routing_audit=passed'
} finally {
    $client.Dispose()
    $handler.Dispose()
}
