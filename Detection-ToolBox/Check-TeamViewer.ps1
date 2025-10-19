#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

param(
    [string]$ConfigPath = "E:\Users\jerom\source\AD-Computer-IMS\config\appsettings.json"
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Find-TeamViewerDevices {
    Write-Host "`n=== INVESTIGATING TEAMVIEWER INSTALLATIONS ===" -ForegroundColor Cyan
    
    # Check device inventory for TeamViewer mentions
    $inventoryPath = "E:\Users\jerom\source\AD-Computer-IMS\output"
    $latestInventory = Get-ChildItem -Path $inventoryPath -Filter "DeviceInventory_Enhanced_*.csv" | 
        Sort-Object CreationTime -Descending | Select-Object -First 1
    
    if ($latestInventory) {
        Write-Host "Analyzing inventory: $($latestInventory.Name)" -ForegroundColor Gray
        $devices = Import-Csv $latestInventory.FullName
        
        # Look for devices that might have TeamViewer
        # Note: This is based on your observation, we'll need to check via Intune for actual installs
        Write-Host "`n🔍 CHECKING FOR POTENTIAL TEAMVIEWER TARGETS..." -ForegroundColor Yellow
        
        # Focus on managed, compliant devices first
        $managedDevices = $devices | Where-Object {
            $_.IsManaged -eq "True" -and
            $_.IsCompliant -eq "True" -and
            $_.OperatingSystem -like "*Windows*"
        } | Sort-Object LastSignIn -Descending
        
        Write-Host "`n📱 MANAGED DEVICES (Best TeamViewer Candidates):" -ForegroundColor Green
        foreach ($device in $managedDevices | Select-Object -First 10) {
            Write-Host "`n🖥️  $($device.DeviceName)" -ForegroundColor White
            Write-Host "   Primary User: $($device.PrimaryUser)" -ForegroundColor Gray
            Write-Host "   Last Activity: $($device.LastSignIn)" -ForegroundColor Gray
            Write-Host "   Management Agent: $($device.ManagementAgent)" -ForegroundColor Gray
            Write-Host "   Special Notes: $($device.SpecialNotes)" -ForegroundColor Cyan
            
            # Highlight key targets
            if ($device.DeviceName -like "*ADMIN*" -or $device.SpecialNotes -like "*Admin*") {
                Write-Host "   ⭐ HIGH PRIORITY - Admin/Infrastructure device!" -ForegroundColor Red
            }
            if ($device.DeviceName -like "desktop-tn5mjd9") {
                Write-Host "   🎯 STEPPING STONE - Can reach PCWAD1!" -ForegroundColor Green
            }
        }
        
        return $managedDevices
    }
    
    return $null
}

function Get-TeamViewerInstalledApps {
    param($DeviceList)
    
    Write-Host "`n=== CHECKING INTUNE FOR TEAMVIEWER INSTALLATIONS ===" -ForegroundColor Cyan
    
    try {
        # Get managed devices from Intune
        $intuneDevices = Get-MgDeviceManagementManagedDevice -All
        
        $teamViewerDevices = @()
        $deviceCount = 0
        $totalDevices = $intuneDevices.Count
        
        Write-Host "Scanning $totalDevices managed devices for TeamViewer..." -ForegroundColor Yellow
        
        foreach ($intuneDevice in $intuneDevices) {
            $deviceCount++
            Write-Progress -Activity "Scanning for TeamViewer" -Status "Device $deviceCount of $totalDevices" -PercentComplete (($deviceCount / $totalDevices) * 100)
            
            try {
                # Get detected apps on device
                $detectedApps = Get-MgDeviceManagementManagedDeviceDetectedApp -ManagedDeviceId $intuneDevice.Id -ErrorAction SilentlyContinue
                
                # Check for TeamViewer in detected apps
                $teamViewerApps = $detectedApps | Where-Object { 
                    $_.DisplayName -like "*TeamViewer*" -or 
                    $_.DisplayName -like "*Team Viewer*"
                }
                
                if ($teamViewerApps) {
                    $deviceInfo = [PSCustomObject]@{
                        DeviceName = $intuneDevice.DeviceName
                        UserDisplayName = $intuneDevice.UserDisplayName
                        UserPrincipalName = $intuneDevice.UserPrincipalName
                        LastSyncDateTime = $intuneDevice.LastSyncDateTime
                        OperatingSystem = $intuneDevice.OperatingSystem
                        TeamViewerApps = $teamViewerApps
                        IntuneDeviceId = $intuneDevice.Id
                    }
                    
                    $teamViewerDevices += $deviceInfo
                    
                    Write-Host "`n✅ FOUND TEAMVIEWER on $($intuneDevice.DeviceName)!" -ForegroundColor Green
                    foreach ($app in $teamViewerApps) {
                        Write-Host "   📱 App: $($app.DisplayName)" -ForegroundColor Cyan
                        Write-Host "   Version: $($app.Version)" -ForegroundColor Gray
                    }
                }
            }
            catch {
                # Skip devices that error out
                Write-Verbose "Could not scan $($intuneDevice.DeviceName): $($_.Exception.Message)"
            }
        }
        
        Write-Progress -Activity "Scanning for TeamViewer" -Completed
        
        if ($teamViewerDevices.Count -gt 0) {
            Write-Host "`n🎯 TEAMVIEWER SUMMARY:" -ForegroundColor Green
            Write-Host "Found TeamViewer on $($teamViewerDevices.Count) devices!" -ForegroundColor White
            
            foreach ($device in $teamViewerDevices) {
                Write-Host "`n📱 $($device.DeviceName)" -ForegroundColor White
                Write-Host "   User: $($device.UserDisplayName)" -ForegroundColor Gray
                Write-Host "   Last Sync: $($device.LastSyncDateTime)" -ForegroundColor Gray
                Write-Host "   Apps: $($device.TeamViewerApps.DisplayName -join ', ')" -ForegroundColor Cyan
            }
            
            return $teamViewerDevices
        } else {
            Write-Host "`n❌ No TeamViewer installations detected via Intune" -ForegroundColor Red
            Write-Host "   This could mean:" -ForegroundColor Gray
            Write-Host "   • TeamViewer is installed but not detected by Intune" -ForegroundColor Gray
            Write-Host "   • TeamViewer is portable/not properly installed" -ForegroundColor Gray
            Write-Host "   • Detection scan hasn't run recently" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "❌ Error scanning for TeamViewer: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    return $null
}

function Create-TeamViewerAccessStrategy {
    param($TeamViewerDevices)
    
    Write-Host "`n=== TEAMVIEWER ACCESS STRATEGY ===" -ForegroundColor Cyan
    
    if ($TeamViewerDevices -and $TeamViewerDevices.Count -gt 0) {
        Write-Host "`n✅ TEAMVIEWER ACCESS POTENTIAL:" -ForegroundColor Green
        
        Write-Host "`n🔑 ACCESS METHODS TO TRY:" -ForegroundColor Yellow
        Write-Host "1. TeamViewer Business Account Access" -ForegroundColor White
        Write-Host "   • Check if Buckhorn has a TeamViewer Business license" -ForegroundColor Gray
        Write-Host "   • Look for corporate TeamViewer credentials" -ForegroundColor Gray
        Write-Host "   • Try admin@buckhorn.org / admin.pcwa@pcwabuckhorn.onmicrosoft.com" -ForegroundColor Gray
        
        Write-Host "`n2. Check for TeamViewer Host Configuration" -ForegroundColor White
        Write-Host "   • Look for unattended access setup" -ForegroundColor Gray
        Write-Host "   • Check if devices are configured for remote access" -ForegroundColor Gray
        
        Write-Host "`n3. Contact Device Users" -ForegroundColor White
        Write-Host "   • Ask users to start TeamViewer and provide session info" -ForegroundColor Gray
        Write-Host "   • Especially focus on admin users or IT-related devices" -ForegroundColor Gray
        
        Write-Host "`n🎯 PRIORITY TARGETS:" -ForegroundColor Yellow
        foreach ($device in $TeamViewerDevices | Select-Object -First 5) {
            Write-Host "   📱 $($device.DeviceName) - User: $($device.UserDisplayName)" -ForegroundColor White
            
            # Check if this device is on our target list
            if ($device.DeviceName -like "*ADMIN*" -or $device.DeviceName -like "desktop-tn5mjd9") {
                Write-Host "      🚀 JACKPOT - This is a high-priority target!" -ForegroundColor Green
            }
        }
        
        Write-Host "`n📋 NEXT ACTIONS:" -ForegroundColor Cyan
        Write-Host "1. Look for TeamViewer account credentials in password managers" -ForegroundColor Yellow
        Write-Host "2. Check email for TeamViewer license/account information" -ForegroundColor Yellow
        Write-Host "3. Try accessing TeamViewer Management Console with admin credentials" -ForegroundColor Yellow
        Write-Host "4. Contact users of devices with TeamViewer installed" -ForegroundColor Yellow
    } else {
        Write-Host "`n❌ NO TEAMVIEWER DETECTED" -ForegroundColor Red
        Write-Host "Alternative approaches:" -ForegroundColor Yellow
        Write-Host "1. Deploy TeamViewer via Intune to target devices" -ForegroundColor White
        Write-Host "2. Use Windows Quick Assist instead" -ForegroundColor White
        Write-Host "3. Enable RDP via Intune scripts" -ForegroundColor White
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Find potential TeamViewer devices
    $candidateDevices = Find-TeamViewerDevices
    
    # Check Intune for actual TeamViewer installations
    Write-Host "`n⚠️  Note: Scanning for TeamViewer requires DeviceManagementApps.Read.All permission" -ForegroundColor Yellow
    $teamViewerDevices = Get-TeamViewerInstalledApps -DeviceList $candidateDevices
    
    # Create access strategy
    Create-TeamViewerAccessStrategy -TeamViewerDevices $teamViewerDevices
    
    Write-Host "`n=== IMMEDIATE STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Check if you have access to TeamViewer Management Console" -ForegroundColor Yellow
    Write-Host "2. Look for TeamViewer credentials in existing documentation" -ForegroundColor Yellow
    Write-Host "3. Try logging into https://login.teamviewer.com with admin accounts" -ForegroundColor Yellow
    Write-Host "4. If successful, look for connected devices in the console" -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to analyze TeamViewer situation: $($_.Exception.Message)"
    
    # Provide manual approach if API fails
    Write-Host "`n🔧 MANUAL TEAMVIEWER CHECK:" -ForegroundColor Yellow
    Write-Host "1. Try logging into TeamViewer Management Console:" -ForegroundColor White
    Write-Host "   https://login.teamviewer.com" -ForegroundColor Cyan
    Write-Host "2. Use these potential accounts:" -ForegroundColor White
    Write-Host "   • admin@buckhorn.org" -ForegroundColor Gray
    Write-Host "   • admin.pcwa@pcwabuckhorn.onmicrosoft.com" -ForegroundColor Gray
    Write-Host "   • charles.felts@buckhorn.org (previous IT admin)" -ForegroundColor Gray
    Write-Host "3. If successful, look for devices in 'Computers & Contacts'" -ForegroundColor White
    
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}