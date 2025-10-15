# Try to locate BUCKHORN_ADMIN specifically
Write-Host "`n=== BUCKHORN_ADMIN HUNT ===" -ForegroundColor Red

# Method 1: Direct hostname resolution
try {
    $adminIP = [System.Net.Dns]::GetHostEntry('BUCKHORN_ADMIN').AddressList[0].IPAddressToString
    Write-Host "✅ BUCKHORN_ADMIN found at: $adminIP" -ForegroundColor Green
    
    # Test access methods
    Write-Host "Testing access methods to BUCKHORN_ADMIN..."
    
    # RDP test
    if (Test-NetConnection -ComputerName $adminIP -Port 3389 -InformationLevel Quiet) {
        Write-Host "  🎯 RDP (3389) is OPEN!" -ForegroundColor Green
    }
    
    # PowerShell remoting test
    if (Test-NetConnection -ComputerName $adminIP -Port 5985 -InformationLevel Quiet) {
        Write-Host "  🎯 WinRM (5985) is OPEN!" -ForegroundColor Green
    }
    
    # SMB test
    if (Test-NetConnection -ComputerName $adminIP -Port 445 -InformationLevel Quiet) {
        Write-Host "  🎯 SMB (445) is OPEN!" -ForegroundColor Green
    }
    
} catch {
    Write-Host "❌ BUCKHORN_ADMIN hostname not resolvable" -ForegroundColor Red
    Write-Host "Checking your device inventory for the IP address..." -ForegroundColor Yellow
}

# Method 2: Check if current user has admin rights on other systems
Write-Host "`nTesting current user's admin rights on discovered devices..."
foreach ($device in $activeDevices) {
    try {
        # Quick admin test - try to access admin share
        if (Test-Path "\\$device\C$" -ErrorAction SilentlyContinue) {
            Write-Host "🚀 ADMIN ACCESS to $device!" -ForegroundColor Red
            
            # Get computer info
            $computerName = (Get-WmiObject -ComputerName $device -Class Win32_ComputerSystem -ErrorAction SilentlyContinue).Name
            Write-Host "  Computer Name: $computerName" -ForegroundColor Cyan
            
            if ($computerName -like "*ADMIN*" -or $computerName -like "*PCWA*") {
                Write-Host "  🎯 POTENTIAL TARGET FOUND!" -ForegroundColor Green
            }
        }
    } catch {
        # Continue silently
    }
}