# Remote Meraki Serial Discovery - Massachusetts to Kentucky Edition
param(
    [string]$MerakiIP = "192.168.102.1",
    [switch]$WebInterfaceMethod,
    [switch]$CertificateMethod,
    [switch]$NetworkMethod,
    [switch]$EmailSearch
)

function Get-RemoteMerakiSerial-WebInterface {
    param([string]$IP)
    
    Write-Host "`n=== REMOTE WEB INTERFACE DISCOVERY ===" -ForegroundColor Cyan
    Write-Host "🌐 Analyzing Meraki web interface from Massachusetts..." -ForegroundColor Yellow
    
    try {
        # Check if we can get device info from login page
        Write-Host "`nTesting: https://$IP" -ForegroundColor Gray
        
        # Try to get web page content
        $webRequest = Invoke-WebRequest -Uri "https://$IP" -TimeoutSec 10 -SkipCertificateCheck -ErrorAction SilentlyContinue
        
        if ($webRequest) {
            Write-Host "✅ Web interface accessible!" -ForegroundColor Green
            
            # Look for serial number in page content
            $content = $webRequest.Content
            
            # Meraki serial patterns
            $serialPatterns = @(
                "Q2[A-Z0-9]{2}-[A-Z0-9]{4}-[A-Z0-9]{4}",  # MX series
                "Q3[A-Z0-9]{2}-[A-Z0-9]{4}-[A-Z0-9]{4}",  # MX series newer
                "[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}"      # General pattern
            )
            
            foreach ($pattern in $serialPatterns) {
                if ($content -match $pattern) {
                    Write-Host "🎯 POTENTIAL SERIAL FOUND: $($matches[0])" -ForegroundColor Red
                    Write-Host "Try login: $($matches[0]) / [blank password]" -ForegroundColor Yellow
                    return $matches[0]
                }
            }
            
            # Look for device model info
            if ($content -match "MX[0-9]{2,3}|Z[0-9]{1,2}") {
                Write-Host "📱 Device model detected: $($matches[0])" -ForegroundColor Cyan
            }
            
            # Check page title
            Write-Host "`nPage title: $($webRequest.ParsedHtml.title)" -ForegroundColor Gray
            
            Write-Host "`n💡 MANUAL STEPS:" -ForegroundColor Yellow
            Write-Host "1. Open https://$IP in browser" -ForegroundColor White
            Write-Host "2. Right-click → View Page Source" -ForegroundColor White
            Write-Host "3. Ctrl+F search for: 'serial', 'Q2', 'device'" -ForegroundColor White
            Write-Host "4. Check login page footer/header for device info" -ForegroundColor White
            
        } else {
            Write-Host "❌ Cannot access web interface remotely" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Web interface check failed: $($_.Exception.Message)" -ForegroundColor Red
        
        Write-Host "`n🔧 TROUBLESHOOTING:" -ForegroundColor Yellow
        Write-Host "• Try HTTP instead: http://$IP" -ForegroundColor White
        Write-Host "• Check if device is accessible via Splashtop" -ForegroundColor White
        Write-Host "• Verify you're still connected to Buckhorn network" -ForegroundColor White
    }
}

function Search-EmailForMerakiInfo {
    Write-Host "`n=== EMAIL ARCHAEOLOGY FOR MERAKI INFO ===" -ForegroundColor Cyan
    
    Write-Host "🔍 Search Buckhorn email systems for:" -ForegroundColor Yellow
    
    $searchTerms = @(
        "meraki dashboard",
        "dashboard.meraki.com", 
        "Q2*-*-* serial",
        "MX* configuration",
        "unified technologies meraki",
        "cisco meraki",
        "network appliance serial",
        "meraki organization"
    )
    
    Write-Host "`n📧 EMAIL SEARCH TERMS:" -ForegroundColor Yellow
    $searchTerms | ForEach-Object {
        Write-Host "   • $_" -ForegroundColor White
    }
    
    Write-Host "`n💼 LIKELY EMAIL LOCATIONS:" -ForegroundColor Cyan
    Write-Host "• IT admin's sent/received folders" -ForegroundColor White
    Write-Host "• Meraki account setup emails" -ForegroundColor White
    Write-Host "• Network documentation attachments" -ForegroundColor White
    Write-Host "• Vendor communications" -ForegroundColor White
    Write-Host "• Purchase orders/receipts" -ForegroundColor White
}

function Get-NetworkDiscoveryClues {
    param([string]$IP)
    
    Write-Host "`n=== NETWORK-BASED CLUES ===" -ForegroundColor Cyan
    
    Write-Host "🔍 Gathering network intel about $IP..." -ForegroundColor Yellow
    
    # Get MAC address
    try {
        $arpResult = arp -a | Where-Object { $_ -match $IP }
        if ($arpResult) {
            $macAddress = ($arpResult -split '\s+')[1]
            Write-Host "MAC Address: $macAddress" -ForegroundColor Green
            
            # Cisco OUI check
            $ciscoOUIs = @("00-18-0A", "88-15-44", "E0-CB-BC", "58-97-BD", "34-DB-FD", "AC-17-C8")
            $macPrefix = $macAddress.Substring(0, 8)
            
            if ($ciscoOUIs -contains $macPrefix) {
                Write-Host "✅ Confirmed Cisco device (MAC OUI match)" -ForegroundColor Green
            }
            
            Write-Host "`n💡 MAC Lookup: https://maclookup.app/$macAddress" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "Could not retrieve MAC address" -ForegroundColor Gray
    }
    
    # Check DHCP logs if we're on domain controller
    Write-Host "`n🔍 DHCP Investigation (if available):" -ForegroundColor Yellow
    Write-Host "Get-DhcpServerv4Lease | Where-Object {`$_.IPAddress -eq '$IP'}" -ForegroundColor Cyan
    Write-Host "Get-DhcpServerv4Reservation | Where-Object {`$_.IPAddress -eq '$IP'}" -ForegroundColor Cyan
}

function Get-AlternativeAccess {
    Write-Host "`n=== ALTERNATIVE ACCESS STRATEGIES ===" -ForegroundColor Red
    
    Write-Host "🎯 REMOTE ACCESS OPTIONS:" -ForegroundColor Yellow
    
    Write-Host "`n1. MERAKI DASHBOARD ORGANIZATION SEARCH:" -ForegroundColor White
    Write-Host "   • Go to https://dashboard.meraki.com" -ForegroundColor Cyan
    Write-Host "   • Try common Buckhorn email addresses" -ForegroundColor Gray
    Write-Host "   • Search for organizations containing 'Buckhorn' or 'PCWA'" -ForegroundColor Gray
    Write-Host "   • Look for 'Unified Technologies' organization" -ForegroundColor Gray
    
    Write-Host "`n2. CISCO/MERAKI SUPPORT LOOKUP:" -ForegroundColor White
    Write-Host "   • Contact Cisco with MAC address" -ForegroundColor Gray
    Write-Host "   • Provide proof of ownership" -ForegroundColor Gray
    Write-Host "   • They can provide serial number" -ForegroundColor Gray
    
    Write-Host "`n3. NETWORK DISCOVERY TOOLS:" -ForegroundColor White
    Write-Host "   • Cisco Discovery Protocol (CDP) if available" -ForegroundColor Gray
    Write-Host "   • LLDP neighbor discovery" -ForegroundColor Gray
    Write-Host "   • SNMP walk (if community strings known)" -ForegroundColor Gray
    
    Write-Host "`n4. PREVIOUS IT DOCUMENTATION HUNT:" -ForegroundColor White
    Write-Host "   • Network diagrams" -ForegroundColor Gray
    Write-Host "   • Asset management systems" -ForegroundColor Gray
    Write-Host "   • Purchase records" -ForegroundColor Gray
    Write-Host "   • Configuration backups" -ForegroundColor Gray
}

try {
    Write-Host "=== REMOTE MERAKI SERIAL DISCOVERY ===" -ForegroundColor Red
    Write-Host "🌍 Massachusetts → Kentucky Remote Network Investigation" -ForegroundColor Yellow
    Write-Host "Target: $MerakiIP (Cisco Meraki MX Security Appliance)" -ForegroundColor Cyan
    
    if ($WebInterfaceMethod) {
        $foundSerial = Get-RemoteMerakiSerial-WebInterface -IP $MerakiIP
    }
    
    if ($NetworkMethod) {
        Get-NetworkDiscoveryClues -IP $MerakiIP
    }
    
    if ($EmailSearch) {
        Search-EmailForMerakiInfo
    }
    
    Get-AlternativeAccess
    
    Write-Host "`n🎯 TONIGHT'S HOMEWORK:" -ForegroundColor Red
    Write-Host "1. Search Buckhorn emails for Meraki references" -ForegroundColor Yellow
    Write-Host "2. Try accessing https://dashboard.meraki.com" -ForegroundColor Yellow
    Write-Host "3. Look for 'Unified Technologies' organization" -ForegroundColor Yellow
    Write-Host "4. Check if any Buckhorn emails have Meraki dashboard access" -ForegroundColor Yellow
    
    Write-Host "`n📞 TOMORROW'S KENTUCKY MISSION:" -ForegroundColor Green
    Write-Host "Have someone check the physical device label for serial number!" -ForegroundColor Yellow
    Write-Host "Format to look for: Q2XX-XXXX-XXXX" -ForegroundColor White
    
} catch {
    Write-Error "Remote discovery error: $($_.Exception.Message)"
}