# Network Equipment Analyzer for Buckhorn Discovery
param(
    [string[]]$TargetIPs = @("192.168.102.1", "192.168.102.20"),
    [switch]$WebInterface,
    [switch]$DetailedScan,
    [switch]$VPNDetection
)

function Test-WebInterface {
    param([string]$IPAddress)
    
    Write-Host "`n=== WEB INTERFACE ANALYSIS: $IPAddress ===" -ForegroundColor Cyan
    
    $protocols = @("https", "http")
    
    foreach ($protocol in $protocols) {
        $url = "$protocol`://$IPAddress"
        
        try {
            Write-Host "Testing $url..." -NoNewline
            
            # Create web request with timeout
            $request = [System.Net.WebRequest]::Create($url)
            $request.Timeout = 5000
            $request.AllowAutoRedirect = $false
            
            # Ignore SSL certificate errors for HTTPS
            if ($protocol -eq "https") {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            }
            
            $response = $request.GetResponse()
            $statusCode = $response.StatusCode
            
            # Try to get server header
            $serverHeader = $response.Headers["Server"]
            $contentType = $response.ContentType
            
            Write-Host " SUCCESS ($statusCode)" -ForegroundColor Green
            Write-Host "    Server: $serverHeader" -ForegroundColor Gray
            Write-Host "    Content-Type: $contentType" -ForegroundColor Gray
            
            # Try to read a bit of content to identify device
            if ($response.ContentLength -gt 0 -and $response.ContentLength -lt 10000) {
                $stream = $response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
                $reader.Close()
                
                # Look for vendor indicators in HTML
                $vendorClues = @{
                    "SonicWall" = "sonicwall|sonic"
                    "Cisco" = "cisco|asdm"
                    "Fortinet" = "fortinet|fortigate"
                    "pfSense" = "pfsense"
                    "Ubiquiti" = "ubnt|ubiquiti|unifi"
                    "Netgear" = "netgear"
                    "TP-Link" = "tp-link|tplink"
                    "Linksys" = "linksys"
                    "D-Link" = "d-link|dlink"
                    "Meraki" = "meraki"
                }
                
                foreach ($vendor in $vendorClues.Keys) {
                    if ($content -match $vendorClues[$vendor]) {
                        Write-Host "    🎯 VENDOR DETECTED: $vendor" -ForegroundColor Yellow
                        
                        # VPN capability hints
                        if ($vendor -in @("SonicWall", "Cisco", "Fortinet", "pfSense")) {
                            Write-Host "    🔒 VPN CAPABLE DEVICE!" -ForegroundColor Green
                        }
                        break
                    }
                }
                
                # Look for login pages
                if ($content -match "login|username|password|authentication") {
                    Write-Host "    🔐 Login page detected" -ForegroundColor Cyan
                }
                
                # Look for VPN-related terms
                $vpnTerms = @("vpn", "ipsec", "ssl-vpn", "remote access", "anyconnect", "global protect")
                foreach ($term in $vpnTerms) {
                    if ($content -match $term) {
                        Write-Host "    🌐 VPN FEATURE DETECTED: $term" -ForegroundColor Green
                    }
                }
            }
            
            $response.Close()
            
        } catch {
            Write-Host " Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Test-DetailedPorts {
    param([string]$IPAddress)
    
    Write-Host "`n=== DETAILED PORT SCAN: $IPAddress ===" -ForegroundColor Cyan
    
    # Common network device ports
    $networkPorts = @{
        21 = "FTP"
        22 = "SSH"
        23 = "Telnet"
        53 = "DNS"
        80 = "HTTP"
        443 = "HTTPS"
        161 = "SNMP"
        162 = "SNMP Trap"
        389 = "LDAP"
        636 = "LDAPS"
        993 = "IMAPS"
        995 = "POP3S"
        1194 = "OpenVPN"
        1723 = "PPTP VPN"
        4433 = "OpenVPN Alt"
        4500 = "IPSec NAT-T"
        500 = "IPSec IKE"
        8080 = "HTTP Alt"
        8443 = "HTTPS Alt"
        10443 = "Cisco ASDM"
    }
    
    $openPorts = @()
    
    foreach ($port in $networkPorts.Keys) {
        Write-Host "Testing port $port ($($networkPorts[$port]))..." -NoNewline
        
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($IPAddress, $port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(1000, $false)
        
        if ($wait -and $tcpClient.Connected) {
            Write-Host " OPEN" -ForegroundColor Green
            $openPorts += "$port ($($networkPorts[$port]))"
            
            # Special VPN port detection
            if ($port -in @(1194, 1723, 4500, 500)) {
                Write-Host "    🎯 VPN PORT DETECTED!" -ForegroundColor Red
            }
        } else {
            Write-Host " Closed" -ForegroundColor Gray
        }
        
        $tcpClient.Close()
    }
    
    return $openPorts
}

function Analyze-VPNCapabilities {
    param([string]$IPAddress, [array]$OpenPorts)
    
    Write-Host "`n=== VPN CAPABILITY ANALYSIS: $IPAddress ===" -ForegroundColor Red
    
    $vpnScore = 0
    $vpnFeatures = @()
    
    # Check for VPN-related ports
    if ($OpenPorts -match "500|4500") {
        $vpnScore += 3
        $vpnFeatures += "IPSec capable (IKE ports open)"
    }
    
    if ($OpenPorts -match "1194") {
        $vpnScore += 3
        $vpnFeatures += "OpenVPN capable"
    }
    
    if ($OpenPorts -match "1723") {
        $vpnScore += 2
        $vpnFeatures += "PPTP VPN capable"
    }
    
    if ($OpenPorts -match "443") {
        $vpnScore += 2
        $vpnFeatures += "SSL VPN potential (HTTPS available)"
    }
    
    if ($OpenPorts -match "22") {
        $vpnScore += 1
        $vpnFeatures += "SSH tunnel potential"
    }
    
    # Determine VPN likelihood
    $vpnLikelihood = switch ($vpnScore) {
        {$_ -ge 5} { "HIGH - Multiple VPN protocols detected" }
        {$_ -ge 3} { "MEDIUM - Some VPN capabilities detected" }
        {$_ -ge 1} { "LOW - Basic remote access possible" }
        default { "NONE - No VPN indicators found" }
    }
    
    Write-Host "VPN Likelihood: $vpnLikelihood" -ForegroundColor $(if($vpnScore -ge 3){'Green'}else{'Yellow'})
    
    if ($vpnFeatures) {
        Write-Host "VPN Features Detected:" -ForegroundColor Cyan
        $vpnFeatures | ForEach-Object { Write-Host "  • $_" -ForegroundColor White }
    }
    
    return @{
        Score = $vpnScore
        Likelihood = $vpnLikelihood
        Features = $vpnFeatures
    }
}

try {
    Write-Host "=== BUCKHORN NETWORK EQUIPMENT ANALYZER ===" -ForegroundColor Red
    
    foreach ($ip in $TargetIPs) {
        Write-Host "`n" + "="*60 -ForegroundColor Yellow
        Write-Host "ANALYZING: $ip" -ForegroundColor Yellow
        Write-Host "="*60 -ForegroundColor Yellow
        
        if ($WebInterface) {
            Test-WebInterface -IPAddress $ip
        }
        
        if ($DetailedScan) {
            $detailedPorts = Test-DetailedPorts -IPAddress $ip
            
            if ($VPNDetection) {
                Analyze-VPNCapabilities -IPAddress $ip -OpenPorts $detailedPorts
            }
        }
        
        Write-Host "`n💡 NEXT STEPS FOR $ip" -ForegroundColor Cyan
        Write-Host "1. Try accessing web interface: https://$ip or http://$ip" -ForegroundColor White
        Write-Host "2. Look for default login credentials online" -ForegroundColor White
        Write-Host "3. Check for SNMP community strings (if port 161 open)" -ForegroundColor White
        if ($ip -eq "192.168.102.20") {
            Write-Host "4. SSH access available - try common usernames" -ForegroundColor White
        }
    }
    
    Write-Host "`n🎯 SUMMARY RECOMMENDATIONS:" -ForegroundColor Red
    Write-Host "• 192.168.102.1 - Primary gateway, check for VPN server settings" -ForegroundColor Yellow
    Write-Host "• 192.168.102.20 - Enterprise device with SSH, likely VPN capable" -ForegroundColor Yellow
    Write-Host "• Both devices have web interfaces - try accessing them!" -ForegroundColor Green
    
} catch {
    Write-Error "Network analysis error: $($_.Exception.Message)"
}