#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

param(
    [string]$ConfigPath = "E:\Users\jerom\source\AD-Computer-IMS\config\appsettings.json",
    [switch]$ScanForRemotePC,
    [switch]$AnalyzeCredentials
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Find-RemotePCDevices {
    Write-Host "`n=== INVESTIGATING REMOTE PC INSTALLATIONS ===" -ForegroundColor Cyan
    Write-Host "Remote PC is perfect for unattended access - this could be your golden ticket!" -ForegroundColor Green
    
    # Check device inventory for potential Remote PC devices
    $inventoryPath = "E:\Users\jerom\source\AD-Computer-IMS\output"
    $latestInventory = Get-ChildItem -Path $inventoryPath -Filter "DeviceInventory_Enhanced_*.csv" | 
        Sort-Object CreationTime -Descending | Select-Object -First 1
    
    if ($latestInventory) {
        Write-Host "Analyzing inventory: $($latestInventory.Name)" -ForegroundColor Gray
        $devices = Import-Csv $latestInventory.FullName
        
        # Focus on managed devices that could have Remote PC
        $managedDevices = $devices | Where-Object {
            $_.IsManaged -eq "True" -and
            $_.OperatingSystem -like "*Windows*"
        } | Sort-Object LastSignIn -Descending
        
        Write-Host "`n📱 POTENTIAL REMOTE PC TARGETS:" -ForegroundColor Yellow
        foreach ($device in $managedDevices | Select-Object -First 15) {
            Write-Host "`n🖥️  $($device.DeviceName)" -ForegroundColor White
            Write-Host "   Primary User: $($device.PrimaryUser)" -ForegroundColor Gray
            Write-Host "   Last Activity: $($device.LastSignIn)" -ForegroundColor Gray
            Write-Host "   Compliant: $($device.IsCompliant)" -ForegroundColor Gray
            
            # Highlight high-value targets
            if ($device.DeviceName -like "*ADMIN*" -or $device.SpecialNotes -like "*Admin*") {
                Write-Host "   🎯 HIGH PRIORITY - Admin device!" -ForegroundColor Red
            }
            if ($device.DeviceName -like "desktop-tn5mjd9") {
                Write-Host "   🚀 STEPPING STONE - Can reach PCWAD1!" -ForegroundColor Green
            }
            if ($device.DeviceName -like "*PCWA*") {
                Write-Host "   🏢 INFRASTRUCTURE - PCWA network device" -ForegroundColor Cyan
            }
        }
        
        return $managedDevices
    }
    
    return $null
}

function Scan-IntuneForRemotePC {
    Write-Host "`n=== SCANNING INTUNE FOR REMOTE PC SOFTWARE ===" -ForegroundColor Cyan
    
    try {
        # Get managed devices from Intune
        $intuneDevices = Get-MgDeviceManagementManagedDevice -All
        
        $remotePCDevices = @()
        $deviceCount = 0
        $totalDevices = $intuneDevices.Count
        
        Write-Host "Scanning $totalDevices managed devices for Remote PC..." -ForegroundColor Yellow
        
        foreach ($intuneDevice in $intuneDevices) {
            $deviceCount++
            Write-Progress -Activity "Scanning for Remote PC" -Status "Device $deviceCount of $totalDevices" -PercentComplete (($deviceCount / $totalDevices) * 100)
            
            try {
                # Get detected apps on device
                $detectedApps = Get-MgDeviceManagementManagedDeviceDetectedApp -ManagedDeviceId $intuneDevice.Id -ErrorAction SilentlyContinue
                
                # Check for Remote PC in detected apps
                $remotePCApps = $detectedApps | Where-Object { 
                    $_.DisplayName -like "*Remote PC*" -or 
                    $_.DisplayName -like "*RemotePC*" -or
                    $_.Publisher -like "*Remote PC*"
                }
                
                if ($remotePCApps) {
                    $deviceInfo = [PSCustomObject]@{
                        DeviceName = $intuneDevice.DeviceName
                        UserDisplayName = $intuneDevice.UserDisplayName
                        UserPrincipalName = $intuneDevice.UserPrincipalName
                        LastSyncDateTime = $intuneDevice.LastSyncDateTime
                        OperatingSystem = $intuneDevice.OperatingSystem
                        RemotePCApps = $remotePCApps
                        IntuneDeviceId = $intuneDevice.Id
                        IsHighPriority = ($intuneDevice.DeviceName -like "*ADMIN*" -or 
                                        $intuneDevice.DeviceName -like "desktop-tn5mjd9" -or
                                        $intuneDevice.DeviceName -like "*PCWA*")
                    }
                    
                    $remotePCDevices += $deviceInfo
                    
                    Write-Host "`n✅ FOUND REMOTE PC on $($intuneDevice.DeviceName)!" -ForegroundColor Green
                    foreach ($app in $remotePCApps) {
                        Write-Host "   📱 App: $($app.DisplayName)" -ForegroundColor Cyan
                        Write-Host "   Version: $($app.Version)" -ForegroundColor Gray
                        Write-Host "   Publisher: $($app.Publisher)" -ForegroundColor Gray
                    }
                    
                    if ($deviceInfo.IsHighPriority) {
                        Write-Host "   🚀 HIGH PRIORITY TARGET!" -ForegroundColor Red
                    }
                }
            }
            catch {
                Write-Verbose "Could not scan $($intuneDevice.DeviceName): $($_.Exception.Message)"
            }
        }
        
        Write-Progress -Activity "Scanning for Remote PC" -Completed
        
        if ($remotePCDevices.Count -gt 0) {
            Write-Host "`n🎯 REMOTE PC SUMMARY:" -ForegroundColor Green
            Write-Host "Found Remote PC on $($remotePCDevices.Count) devices!" -ForegroundColor White
            
            # Sort by priority
            $sortedDevices = $remotePCDevices | Sort-Object IsHighPriority -Descending
            
            foreach ($device in $sortedDevices) {
                Write-Host "`n📱 $($device.DeviceName)" -ForegroundColor White
                Write-Host "   User: $($device.UserDisplayName)" -ForegroundColor Gray
                Write-Host "   Last Sync: $($device.LastSyncDateTime)" -ForegroundColor Gray
                Write-Host "   Apps: $($device.RemotePCApps.DisplayName -join ', ')" -ForegroundColor Cyan
                
                if ($device.IsHighPriority) {
                    Write-Host "   ⭐ PRIORITY TARGET" -ForegroundColor Red
                }
            }
            
            return $remotePCDevices
        } else {
            Write-Host "`n❌ No Remote PC installations detected via Intune" -ForegroundColor Red
            Write-Host "   But you mentioned seeing it on devices - it might be:" -ForegroundColor Gray
            Write-Host "   • Installed as portable software" -ForegroundColor Gray
            Write-Host "   • Not detected by Intune scanning yet" -ForegroundColor Gray
            Write-Host "   • Installed outside of managed deployment" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "❌ Error scanning for Remote PC: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   This might be due to missing DeviceManagementApps.Read.All permission" -ForegroundColor Yellow
    }
    
    return $null
}

function Analyze-RemotePCCredentials {
    Write-Host "`n=== REMOTE PC ACCOUNT REACTIVATION STRATEGY ===" -ForegroundColor Cyan
    
    Write-Host "`n📋 REMOTE PC ACCOUNT INFORMATION FROM CEO'S PAPERS:" -ForegroundColor Yellow
    Write-Host "Status: Expired over a year ago" -ForegroundColor Red
    Write-Host "This suggests it was actively used for IT management!" -ForegroundColor Green
    
    Write-Host "`n🔑 ACCOUNT RECOVERY STEPS:" -ForegroundColor Yellow
    Write-Host "1. FIND THE ACCOUNT DETAILS:" -ForegroundColor White
    Write-Host "   • Check the admin passwords paper for Remote PC credentials" -ForegroundColor Gray
    Write-Host "   • Look for email address associated with Remote PC account" -ForegroundColor Gray
    Write-Host "   • Check for any Remote PC subscription/billing emails" -ForegroundColor Gray
    
    Write-Host "`n2. TRY LOGGING INTO REMOTE PC CONSOLE:" -ForegroundColor White
    Write-Host "   • Go to https://www.remotepc.com/login" -ForegroundColor Cyan
    Write-Host "   • Try credentials from the admin papers" -ForegroundColor Gray
    Write-Host "   • Look for 'Account Suspended' or 'Expired' messages" -ForegroundColor Gray
    
    Write-Host "`n3. REACTIVATE THE SUBSCRIPTION:" -ForegroundColor White
    Write-Host "   • If login works but subscription expired, reactivate it" -ForegroundColor Gray
    Write-Host "   • Remote PC typically retains device list even after expiration" -ForegroundColor Gray
    Write-Host "   • Devices may still have Remote PC software installed" -ForegroundColor Gray
    
    Write-Host "`n4. POTENTIAL CREDENTIALS TO TRY:" -ForegroundColor White
    Write-Host "   • admin@buckhorn.org" -ForegroundColor Gray
    Write-Host "   • admin.pcwa@pcwabuckhorn.onmicrosoft.com" -ForegroundColor Gray
    Write-Host "   • charles.felts@buckhorn.org (previous IT admin)" -ForegroundColor Gray
    Write-Host "   • Any email addresses from the admin papers" -ForegroundColor Gray
    
    Write-Host "`n💡 WHY THIS IS PROMISING:" -ForegroundColor Cyan
    Write-Host "✅ Remote PC is designed for unattended access" -ForegroundColor Green
    Write-Host "✅ Expired accounts often retain device lists" -ForegroundColor Green
    Write-Host "✅ Software may still be installed on devices" -ForegroundColor Green
    Write-Host "✅ Reactivation usually restores full access immediately" -ForegroundColor Green
    Write-Host "✅ Perfect for accessing desktop-tn5mjd9 and other targets" -ForegroundColor Green
    
    Write-Host "`n🎯 SUCCESS SCENARIO:" -ForegroundColor Green
    Write-Host "If reactivation works, you could have immediate remote access to:" -ForegroundColor White
    Write-Host "• desktop-tn5mjd9 (your stepping stone to PCWAD1)" -ForegroundColor Yellow
    Write-Host "• BUCKHORN_ADMIN (potential jumpbox)" -ForegroundColor Yellow
    Write-Host "• Any other devices with Remote PC installed" -ForegroundColor Yellow
    
    Write-Host "`n📋 IMMEDIATE ACTION PLAN:" -ForegroundColor Cyan
    Write-Host "1. Locate Remote PC credentials in admin papers" -ForegroundColor Yellow
    Write-Host "2. Try logging into Remote PC web console" -ForegroundColor Yellow
    Write-Host "3. If expired, reactivate subscription" -ForegroundColor Yellow
    Write-Host "4. Check for connected devices in console" -ForegroundColor Yellow
    Write-Host "5. Connect to highest priority targets first" -ForegroundColor Yellow
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Find potential Remote PC devices
    $candidateDevices = Find-RemotePCDevices
    
    if ($ScanForRemotePC) {
        # Scan Intune for actual Remote PC installations
        $remotePCDevices = Scan-IntuneForRemotePC
    }
    
    if ($AnalyzeCredentials) {
        # Analyze Remote PC credential recovery
        Analyze-RemotePCCredentials
    }
    
    Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "🔍 IMMEDIATE ACTIONS:" -ForegroundColor Yellow
    Write-Host "1. Check admin papers for Remote PC account details" -ForegroundColor White
    Write-Host "2. Try logging into https://www.remotepc.com/login" -ForegroundColor White
    Write-Host "3. If account exists but expired, reactivate subscription" -ForegroundColor White
    Write-Host "4. Look for device list in Remote PC console" -ForegroundColor White
    Write-Host "5. Target desktop-tn5mjd9 and ADMIN devices first" -ForegroundColor White
    
    Write-Host "`n🚀 SCANNING COMMANDS:" -ForegroundColor Yellow
    Write-Host ".\Check-RemotePC.ps1 -ScanForRemotePC     # Scan Intune for Remote PC" -ForegroundColor Gray
    Write-Host ".\Check-RemotePC.ps1 -AnalyzeCredentials  # Get credential recovery guide" -ForegroundColor Gray
    
} catch {
    Write-Error "Failed to analyze Remote PC situation: $($_.Exception.Message)"
    
    Write-Host "`n🔧 MANUAL REMOTE PC CHECK:" -ForegroundColor Yellow
    Write-Host "1. Check admin papers for Remote PC credentials" -ForegroundColor White
    Write-Host "2. Try logging into Remote PC Management Console:" -ForegroundColor White
    Write-Host "   https://www.remotepc.com/login" -ForegroundColor Cyan
    Write-Host "3. Look for 'Reactivate Account' or billing options" -ForegroundColor White
    Write-Host "4. Remote PC often retains device lists even after expiration" -ForegroundColor White
    
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}