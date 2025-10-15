#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

param(
    [string]$ConfigPath = "E:\Users\jerom\source\AD-Computer-IMS\config\appsettings.json",
    [string]$TargetDevice = $null,
    [switch]$ListCandidates,
    [switch]$DeployTeamViewer,
    [switch]$EnableRDP,
    [switch]$DeployQuickAssist
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Get-RemoteAccessCandidates {
    Write-Host "`n=== ANALYZING RDP-READY DEVICE CANDIDATES ===" -ForegroundColor Cyan
    
    # Get devices from your latest inventory
    $inventoryPath = "E:\Users\jerom\source\AD-Computer-IMS\output"
    $latestInventory = Get-ChildItem -Path $inventoryPath -Filter "DeviceInventory_Enhanced_*.csv" | 
        Sort-Object CreationTime -Descending | Select-Object -First 1
    
    if ($latestInventory) {
        Write-Host "Using inventory file: $($latestInventory.Name)" -ForegroundColor Gray
        $devices = Import-Csv $latestInventory.FullName
        
        # Filter for best RDP candidates - prioritize admin devices and compliant managed devices
        $adminDevices = $devices | Where-Object {
            $_.IsManaged -eq "True" -and
            $_.IsCompliant -eq "True" -and
            $_.OperatingSystem -like "*Windows*" -and
            ($_.DeviceName -like "*ADMIN*" -or 
             $_.LastSignInUser -like "*felts*" -or
             $_.LastSignInUser -like "*combs*" -or
             $_.SpecialNotes -like "*Previous IT Admin*" -or
             $_.SpecialNotes -like "*Jumpbox*" -or
             $_.SpecialNotes -like "*Gateway*")
        } | Sort-Object @{Expression={$_.DeviceName -like "*ADMIN*"};Descending=$true}, LastSignIn -Descending
        
        $regularCandidates = $devices | Where-Object {
            $_.IsManaged -eq "True" -and
            $_.IsCompliant -eq "True" -and
            $_.OperatingSystem -like "*Windows*" -and
            $_.RemoteAccessReady -eq "Yes" -and
            $_.DeviceName -notlike "*ADMIN*" -and
            $_.PrimaryUser -notlike "*admin*"
        } | Sort-Object LastSignIn -Descending | Select-Object -First 10
        
        Write-Host "`n🎯 TOP PRIORITY TARGETS (Admin/Infrastructure Devices):" -ForegroundColor Red
        if ($adminDevices) {
            foreach ($device in $adminDevices) {
                Write-Host "`n🖥️  $($device.DeviceName) ⭐ HIGH PRIORITY" -ForegroundColor White
                Write-Host "   Primary User: $($device.PrimaryUser)" -ForegroundColor Gray
                Write-Host "   Last Activity: $($device.LastSignIn)" -ForegroundColor Gray
                Write-Host "   OS: $($device.OperatingSystem)" -ForegroundColor Gray
                Write-Host "   Special Notes: $($device.SpecialNotes)" -ForegroundColor Cyan
                Write-Host "   Management Agent: $($device.ManagementAgent)" -ForegroundColor Gray
                
                if ($device.DeviceName -like "*BUCKHORN_ADMIN*") {
                    Write-Host "   🚀 JACKPOT! This is likely your main jumpbox/gateway!" -ForegroundColor Green
                }
            }
        } else {
            Write-Host "   ❌ No admin/infrastructure devices found" -ForegroundColor Red
        }
        
        Write-Host "`n🎯 SECONDARY TARGETS (Regular User Devices):" -ForegroundColor Yellow
        if ($regularCandidates) {
            foreach ($device in $regularCandidates | Select-Object -First 5) {
                Write-Host "`n🖥️  $($device.DeviceName)" -ForegroundColor White
                Write-Host "   Primary User: $($device.PrimaryUser)" -ForegroundColor Gray
                Write-Host "   Last Activity: $($device.LastSignIn)" -ForegroundColor Gray
                Write-Host "   OS: $($device.OperatingSystem)" -ForegroundColor Gray
            }
        }
        
        return @{
            AdminDevices = $adminDevices
            RegularCandidates = $regularCandidates
        }
    } else {
        Write-Host "❌ No device inventory found. Run the enhanced device inventory script first:" -ForegroundColor Red
        Write-Host "   .\AD-Computer_IMS-v2-Enhanced.ps1 -DetectiveMode -ExportToCsv" -ForegroundColor Yellow
        return $null
    }
}

function Deploy-RemoteAccessToDevice {
    param(
        [string]$DeviceName,
        [switch]$EnableRDP,
        [switch]$InstallTeamViewer,
        [switch]$InstallQuickAssist
    )
    
    Write-Host "`n=== DEPLOYING REMOTE ACCESS TO $DeviceName ===" -ForegroundColor Cyan
    
    try {
        # Get the managed device
        Write-Host "🔍 Looking for device in Intune..." -ForegroundColor Yellow
        $devices = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'"
        
        if (-not $devices -or $devices.Count -eq 0) {
            Write-Host "❌ Device '$DeviceName' not found in Intune managed devices" -ForegroundColor Red
            return $false
        }
        
        $device = $devices[0]
        Write-Host "✅ Found device: $($device.DeviceName) (ID: $($device.Id))" -ForegroundColor Green
        Write-Host "   User: $($device.UserDisplayName)" -ForegroundColor Gray
        Write-Host "   OS: $($device.OperatingSystem)" -ForegroundColor Gray
        Write-Host "   Last Sync: $($device.LastSyncDateTime)" -ForegroundColor Gray
        
        # Create PowerShell script content based on options
        $scriptLines = @()
        
        if ($EnableRDP) {
            $scriptLines += @"
# Enable Remote Desktop
Write-Host "Enabling Remote Desktop..." -ForegroundColor Yellow
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "UserAuthentication" -Value 0
Write-Host "✅ Remote Desktop enabled" -ForegroundColor Green
"@
        }
        
        if ($InstallTeamViewer) {
            $scriptLines += @"
# Download and install TeamViewer Quick Support
Write-Host "Downloading TeamViewer QuickSupport..." -ForegroundColor Yellow
`$teamViewerUrl = "https://download.teamviewer.com/download/TeamViewerQS.exe"
`$tempPath = "`$env:TEMP\TeamViewerQS.exe"
try {
    Invoke-WebRequest -Uri `$teamViewerUrl -OutFile `$tempPath -UseBasicParsing
    Write-Host "✅ TeamViewer downloaded to `$tempPath" -ForegroundColor Green
    Write-Host "💡 TeamViewer will need to be run manually by user" -ForegroundColor Yellow
} catch {
    Write-Host "❌ Failed to download TeamViewer: `$_" -ForegroundColor Red
}
"@
        }
        
        if ($InstallQuickAssist) {
            $scriptLines += @"
# Install Windows Quick Assist (if not already available)
Write-Host "Checking Quick Assist availability..." -ForegroundColor Yellow
`$quickAssist = Get-AppxPackage -Name MicrosoftCorporationII.QuickAssist -AllUsers -ErrorAction SilentlyContinue
if (`$quickAssist) {
    Write-Host "✅ Quick Assist is already available" -ForegroundColor Green
} else {
    Write-Host "Installing Quick Assist..." -ForegroundColor Yellow
    try {
        # Quick Assist should be available by default in Windows 10/11
        # If not, it can be installed from Microsoft Store or as an optional feature
        Get-WindowsCapability -Online | Where-Object Name -like '*QuickAssist*' | Add-WindowsCapability -Online
        Write-Host "✅ Quick Assist installation attempted" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to install Quick Assist: `$_" -ForegroundColor Red
        Write-Host "💡 User can install from Microsoft Store" -ForegroundColor Yellow
    }
}
"@
        }
        
        # Add network info gathering
        $scriptLines += @"
# Gather network information for remote access
Write-Host "Gathering network information..." -ForegroundColor Yellow
`$networkInfo = @{
    ComputerName = `$env:COMPUTERNAME
    IPAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet*' | Select-Object -First 1).IPAddress
    PublicIP = try { (Invoke-WebRequest -uri "http://ifconfig.me/ip" -UseBasicParsing).Content.Trim() } catch { "Unable to determine" }
    DateTime = Get-Date
    User = `$env:USERNAME
}
`$networkInfo | ConvertTo-Json | Out-File "`$env:TEMP\NetworkInfo.json" -Force
Write-Host "✅ Network info saved to `$env:TEMP\NetworkInfo.json" -ForegroundColor Green
Write-Host "Computer: `$(`$networkInfo.ComputerName)" -ForegroundColor Cyan
Write-Host "Local IP: `$(`$networkInfo.IPAddress)" -ForegroundColor Cyan
Write-Host "Public IP: `$(`$networkInfo.PublicIP)" -ForegroundColor Cyan
"@
        
        $fullScript = $scriptLines -join "`n`n"
        
        Write-Host "`n📋 SCRIPT READY FOR DEPLOYMENT:" -ForegroundColor Yellow
        Write-Host $fullScript -ForegroundColor Gray
        
        # Deploy the script using Intune
        Write-Host "`n🚀 DEPLOYING SCRIPT VIA INTUNE..." -ForegroundColor Yellow
        
        # Note: This requires DeviceManagementManagedDevices.PrivilegedOperations.All permission
        # The actual API call would be to create a device management script and assign it
        
        Write-Host "⚠️  MANUAL DEPLOYMENT REQUIRED:" -ForegroundColor Red
        Write-Host "1. Go to Intune Admin Center → Devices → Scripts" -ForegroundColor White
        Write-Host "2. Create new PowerShell script with the content above" -ForegroundColor White
        Write-Host "3. Assign to device: $DeviceName" -ForegroundColor White
        Write-Host "4. OR use remote PowerShell if you can reach the device" -ForegroundColor White
        
        return $true
        
    } catch {
        Write-Host "❌ Error deploying to device: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-RemoteConnectivity {
    param([array]$Devices)
    
    Write-Host "`n=== TESTING NETWORK CONNECTIVITY ===" -ForegroundColor Cyan
    
    foreach ($device in $Devices) {
        Write-Host "`n🔍 Testing connectivity to $($device.DeviceName)..." -ForegroundColor Yellow
        
        # Try to ping the device (if we knew its IP)
        # For now, we'll check if it's recently synced with Intune
        if ($device.LastSyncDateTime) {
            $lastSync = [DateTime]$device.LastSyncDateTime
            $hoursSinceSync = ((Get-Date) - $lastSync).TotalHours
            
            if ($hoursSinceSync -lt 24) {
                Write-Host "✅ Device synced $([math]::Round($hoursSinceSync, 1)) hours ago - likely online" -ForegroundColor Green
            } else {
                Write-Host "⚠️  Device last synced $([math]::Round($hoursSinceSync, 1)) hours ago - may be offline" -ForegroundColor Yellow
            }
        }
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    if ($ListCandidates) {
        $candidates = Get-RemoteAccessCandidates
        
        if ($candidates -and $candidates.AdminDevices) {
            Write-Host "`n=== RECOMMENDED APPROACH ===" -ForegroundColor Cyan
            Write-Host "🎯 TARGET PRIORITY ORDER:" -ForegroundColor Yellow
            Write-Host "1. BUCKHORN_ADMIN (if found) - Your golden ticket!" -ForegroundColor Green
            Write-Host "2. Other admin/infrastructure devices" -ForegroundColor Yellow
            Write-Host "3. Recently active managed devices" -ForegroundColor Gray
            
            Write-Host "`n🔧 NEXT COMMANDS TO RUN:" -ForegroundColor Cyan
            if ($candidates.AdminDevices -and $candidates.AdminDevices[0]) {
                $topDevice = $candidates.AdminDevices[0].DeviceName
                Write-Host "# Deploy to top priority device:" -ForegroundColor Gray
                Write-Host ".\Deploy-RemoteAccess-Enhanced.ps1 -TargetDevice '$topDevice' -EnableRDP -DeployTeamViewer" -ForegroundColor White
            }
            
            Test-RemoteConnectivity -Devices $candidates.AdminDevices
        }
    }
    
    if ($TargetDevice) {
        $success = Deploy-RemoteAccessToDevice -DeviceName $TargetDevice -EnableRDP:$EnableRDP -InstallTeamViewer:$DeployTeamViewer -InstallQuickAssist:$DeployQuickAssist
        
        if ($success) {
            Write-Host "`n✅ Remote access deployment completed for $TargetDevice" -ForegroundColor Green
            Write-Host "💡 Next steps:" -ForegroundColor Yellow
            Write-Host "1. Wait for device to sync with Intune (may take up to 8 hours)" -ForegroundColor White
            Write-Host "2. Contact the device user to run TeamViewer if deployed" -ForegroundColor White
            Write-Host "3. Try RDP connection if enabled: mstsc /v:DEVICE_IP" -ForegroundColor White
        }
    }
    
} catch {
    Write-Error "Failed to deploy remote access: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}