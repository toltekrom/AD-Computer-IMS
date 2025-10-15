# Network Discovery Script - Run from accounting PC via Remote PC

Write-Host "=== BUCKHORN NETWORK DISCOVERY ===" -ForegroundColor Cyan

# 1. Basic network information
Write-Host "`n1. CURRENT NETWORK POSITION:" -ForegroundColor Yellow
$networkInfo = @{
    ComputerName = $env:COMPUTERNAME
    Domain = $env:USERDOMAIN
    IPAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet*' | Select-Object -First 1).IPAddress
    Gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0').NextHop | Select-Object -First 1
}
$networkInfo | Format-Table -AutoSize

# 2. Test connectivity to known targets
Write-Host "`n2. TESTING KNOWN TARGETS:" -ForegroundColor Yellow
$targets = @{
    'PCWAD1 (DC)' = '192.168.102.230'
    'BUCKHORN_ADMIN' = 'BUCKHORN_ADMIN'  # Try hostname first
}

foreach ($target in $targets.GetEnumerator()) {
    Write-Host "Testing $($target.Key): $($target.Value)"
    
    # Ping test
    $pingResult = Test-NetConnection -ComputerName $target.Value -InformationLevel Quiet
    Write-Host "  Ping: $pingResult" -ForegroundColor $(if($pingResult){'Green'}else{'Red'})
    
    # Common port tests
    $ports = @(3389, 22, 445, 135, 5985)  # RDP, SSH, SMB, RPC, WinRM
    foreach ($port in $ports) {
        $portTest = Test-NetConnection -ComputerName $target.Value -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($portTest) {
            Write-Host "  Port $port`: OPEN" -ForegroundColor Green
        }
    }
}

# 3. Discover other devices on network
Write-Host "`n3. NETWORK DEVICE DISCOVERY:" -ForegroundColor Yellow
$subnet = ($networkInfo.IPAddress -split '\.')[0..2] -join '.'
Write-Host "Scanning subnet: $subnet.0/24"

$activeDevices = @()
1..254 | ForEach-Object {
    $ip = "$subnet.$_"
    if (Test-NetConnection -ComputerName $ip -InformationLevel Quiet -WarningAction SilentlyContinue) {
        $activeDevices += $ip
        Write-Host "  Found: $ip" -ForegroundColor Green
        
        # Try to resolve hostname
        try {
            $hostname = [System.Net.Dns]::GetHostEntry($ip).HostName
            Write-Host "    Hostname: $hostname" -ForegroundColor Cyan
        } catch {
            Write-Host "    Hostname: Unable to resolve" -ForegroundColor Gray
        }
    }
}

# 4. Check for admin shares and services
Write-Host "`n4. CHECKING ADMIN ACCESS:" -ForegroundColor Yellow
foreach ($device in $activeDevices) {
    Write-Host "Checking $device for admin access..."
    
    # Test admin shares
    $shares = @('C$', 'ADMIN$', 'IPC$')
    foreach ($share in $shares) {
        try {
            $path = "\\$device\$share"
            if (Test-Path $path) {
                Write-Host "  ✅ Access to $path" -ForegroundColor Green
            }
        } catch {
            # Silently continue - no access
        }
    }
    
    # Test WinRM/PowerShell remoting
    try {
        $session = Test-WSMan -ComputerName $device -ErrorAction SilentlyContinue
        if ($session) {
            Write-Host "  ✅ WinRM available on $device" -ForegroundColor Green
        }
    } catch {
        # Silently continue
    }
}

# 5. Domain information gathering
Write-Host "`n5. DOMAIN RECONNAISSANCE:" -ForegroundColor Yellow
try {
    # Get domain controllers
    $dcs = nltest /dclist:$env:USERDOMAIN 2>$null
    if ($dcs) {
        Write-Host "Domain Controllers:" -ForegroundColor Cyan
        $dcs | Where-Object { $_ -match '\\\\'} | ForEach-Object {
            Write-Host "  $_" -ForegroundColor White
        }
    }
    
    # Get current user's groups
    Write-Host "`nCurrent User Groups:" -ForegroundColor Cyan
    whoami /groups | Select-String "BUILTIN\\|$env:USERDOMAIN\\" | ForEach-Object {
        Write-Host "  $_" -ForegroundColor White
    }
    
} catch {
    Write-Host "Domain enumeration failed: $($_.Exception.Message)" -ForegroundColor Red
}

# 6. Look for scheduled tasks and services that might indicate admin systems
Write-Host "`n6. LOCAL SYSTEM ANALYSIS:" -ForegroundColor Yellow
Write-Host "Checking for management software..."

$managementSoftware = @(
    "TeamViewer*", "RemotePC*", "*RDP*", "*VNC*", 
    "*Admin*", "*Management*", "*Remote*"
)

Get-WmiObject -Class Win32_Product | Where-Object {
    $name = $_.Name
    $managementSoftware | Where-Object { $name -like $_ }
} | ForEach-Object {
    Write-Host "  Found: $($_.Name)" -ForegroundColor Cyan
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Network Position: $($networkInfo.ComputerName) ($($networkInfo.IPAddress))" -ForegroundColor White
Write-Host "Active Devices Found: $($activeDevices.Count)" -ForegroundColor White
Write-Host "Next: Check devices with open admin ports (3389, 5985, 445)" -ForegroundColor Yellow