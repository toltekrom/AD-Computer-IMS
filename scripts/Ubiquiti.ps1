# Ubiquiti Device Analyzer
param(
    [string]$DeviceIP = "192.168.102.20",
    [switch]$TryDefaultCreds,
    [switch]$AnalyzeConfig
)

function Test-UbiquitiAccess {
    param([string]$IP)
    
    Write-Host "`n=== UBIQUITI LITEAP AC ANALYSIS ===" -ForegroundColor Cyan
    Write-Host "Device: $IP" -ForegroundColor Yellow
    
    # Common Ubiquiti default credentials
    $defaultCreds = @(
        @{Username="ubnt"; Password="ubnt"},
        @{Username="admin"; Password="admin"},
        @{Username="admin"; Password=""},
        @{Username="root"; Password="ubnt"}
    )
    
    Write-Host "`n🔐 COMMON UBIQUITI CREDENTIALS TO TRY:" -ForegroundColor Yellow
    $defaultCreds | ForEach-Object {
        Write-Host "   Username: $($_.Username) | Password: $($_.Password)" -ForegroundColor White
    }
    
    Write-Host "`n🌐 ACCESS METHODS:" -ForegroundColor Cyan
    Write-Host "   Web Interface: https://$IP or http://$IP" -ForegroundColor White
    Write-Host "   SSH Access: ssh ubnt@$IP (if SSH enabled)" -ForegroundColor White
    Write-Host "   Ubiquiti Discovery: Use UBNT Discovery Tool" -ForegroundColor White
    
    # Try to determine device model from web interface
    try {
        $webRequest = Invoke-WebRequest -Uri "http://$IP" -TimeoutSec 5 -ErrorAction SilentlyContinue
        
        if ($webRequest.Content -match "LiteAP|UniFi|airOS") {
            Write-Host "`n✅ CONFIRMED: Ubiquiti device detected" -ForegroundColor Green
            
            # Look for firmware version
            if ($webRequest.Content -match "version.*?(\d+\.\d+\.\d+)") {
                Write-Host "   Firmware version hint: $($matches[1])" -ForegroundColor Gray
            }
            
            # Check for login form
            if ($webRequest.Content -match "username|login") {
                Write-Host "   🔐 Login form detected" -ForegroundColor Cyan
            }
        }
    } catch {
        Write-Host "   Could not analyze web interface" -ForegroundColor Gray
    }
}

function Get-UbiquitiInsights {
    Write-Host "`n=== UBIQUITI LITEAP AC INSIGHTS ===" -ForegroundColor Red
    
    Write-Host "`n📡 DEVICE CAPABILITIES:" -ForegroundColor Yellow
    Write-Host "   • Point-to-point wireless bridge (up to 5km range)" -ForegroundColor White
    Write-Host "   • Wireless access point mode" -ForegroundColor White
    Write-Host "   • Site-to-site connectivity" -ForegroundColor White
    Write-Host "   • Potential VPN replacement (wireless bridge)" -ForegroundColor White
    
    Write-Host "`n🏢 LIKELY BUCKHORN USE CASES:" -ForegroundColor Yellow
    Write-Host "   • Connecting remote buildings/sites wirelessly" -ForegroundColor White
    Write-Host "   • Providing wireless internet to remote areas" -ForegroundColor White
    Write-Host "   • Backup internet connection" -ForegroundColor White
    Write-Host "   • Extending network to outbuildings" -ForegroundColor White
    
    Write-Host "`n🔍 INVESTIGATION PRIORITIES:" -ForegroundColor Red
    Write-Host "   1. Check if it's bridging to remote Buckhorn locations" -ForegroundColor White
    Write-Host "   2. Look for wireless clients connected" -ForegroundColor White
    Write-Host "   3. Examine network topology/configuration" -ForegroundColor White
    Write-Host "   4. Check for VPN tunnels over wireless" -ForegroundColor White
    
    Write-Host "`n💡 BUCKHORN NETWORK THEORY:" -ForegroundColor Cyan
    Write-Host "   This might be how they connect remote offices!" -ForegroundColor Yellow
    Write-Host "   Instead of traditional VPN, they use wireless bridges" -ForegroundColor Yellow
    Write-Host "   This could explain the 'missing' VPN infrastructure" -ForegroundColor Yellow
}

function Get-UbiquitiCommands {
    Write-Host "`n=== UBIQUITI INVESTIGATION COMMANDS ===" -ForegroundColor Cyan
    
    Write-Host "`n🔧 NETWORK DISCOVERY:" -ForegroundColor Yellow
    Write-Host "   # Find other Ubiquiti devices on network" -ForegroundColor Gray
    Write-Host "   nmap -sU -p 10001 192.168.102.0/24" -ForegroundColor White
    Write-Host "   # Ubiquiti discovery protocol scan" -ForegroundColor Gray
    
    Write-Host "`n📡 WIRELESS ANALYSIS:" -ForegroundColor Yellow
    Write-Host "   # Check for wireless signals" -ForegroundColor Gray
    Write-Host "   netsh wlan show interfaces" -ForegroundColor White
    Write-Host "   netsh wlan show profiles" -ForegroundColor White
    
    Write-Host "`n🌐 WEB ACCESS:" -ForegroundColor Yellow
    Write-Host "   # Try these URLs" -ForegroundColor Gray
    Write-Host "   https://192.168.102.20" -ForegroundColor White
    Write-Host "   http://192.168.102.20" -ForegroundColor White
    Write-Host "   # Login with: ubnt/ubnt or admin/admin" -ForegroundColor Gray
}

try {
    Write-Host "=== UBIQUITI LITEAP AC DISCOVERED! ===" -ForegroundColor Red
    
    Test-UbiquitiAccess -IP $DeviceIP
    Get-UbiquitiInsights
    Get-UbiquitiCommands
    
    Write-Host "`n🎯 IMMEDIATE ACTION PLAN:" -ForegroundColor Red
    Write-Host "1. Try accessing http://192.168.102.20 with ubnt/ubnt" -ForegroundColor Yellow
    Write-Host "2. Look for 'Wireless' or 'Bridge' configuration" -ForegroundColor Yellow
    Write-Host "3. Check 'Station List' for connected wireless clients" -ForegroundColor Yellow
    Write-Host "4. Look for 'Link' status - might show remote connections" -ForegroundColor Yellow
    Write-Host "5. Export configuration for documentation" -ForegroundColor Yellow
    
    Write-Host "`n💡 THEORY: This might be Buckhorn's 'VPN' solution!" -ForegroundColor Green
    Write-Host "Instead of traditional VPN, they might use wireless bridges" -ForegroundColor Cyan
    Write-Host "to connect remote buildings/locations wirelessly!" -ForegroundColor Cyan
    
} catch {
    Write-Error "Ubiquiti analysis error: $($_.Exception.Message)"
}