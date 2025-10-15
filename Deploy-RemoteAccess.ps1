#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\appsettings.json"),
    [string]$TargetDevice = $null,
    [switch]$ListCandidates,
    [switch]$DeployTeamViewer,
    [switch]$EnableRDP
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Get-RemoteAccessCandidates {
    Write-Host "`n=== RDP-READY DEVICE CANDIDATES ===" -ForegroundColor Cyan
    
    # Get devices from your inventory
    $inventoryPath = ".\output"
    $latestInventory = Get-ChildItem -Path $inventoryPath -Filter "DeviceInventory_Enhanced_*.csv" | 
        Sort-Object CreationTime -Descending | Select-Object -First 1
    
    if ($latestInventory) {
        $devices = Import-Csv $latestInventory.FullName
        
        # Filter for best RDP candidates
        $candidates = $devices | Where-Object {
            $_.IsManaged -eq "True" -and
            $_.IsCompliant -eq "True" -and
            $_.OperatingSystem -like "*Windows*" -and
            ($_.SpecialNotes -like "*Previous IT Admin*" -or 
             $_.DeviceName -like "*ADMIN*" -or
             $_.PrimaryUser -like "*felts*" -or
             $_.PrimaryUser -like "*combs.*")
        } | Sort-Object LastSignIn -Descending
        
        Write-Host "`n🎯 TOP RDP CANDIDATES:" -ForegroundColor Yellow
        $topCandidates = $candidates | Select-Object -First 10
        
        foreach ($device in $topCandidates) {
            Write-Host "`n🖥️  $($device.DeviceName)" -ForegroundColor White
            Write-Host "   Primary User: $($device.PrimaryUser)" -ForegroundColor Gray
            Write-Host "   Last Activity: $($device.LastSignIn)" -ForegroundColor Gray
            Write-Host "   OS: $($device.OperatingSystem)" -ForegroundColor Gray
            Write-Host "   Notes: $($device.SpecialNotes)" -ForegroundColor Cyan
            Write-Host "   Managed: $($device.IsManaged) | Compliant: $($device.IsCompliant)" -ForegroundColor Gray
        }
        
        return $topCandidates
    } else {
        Write-Host "❌ No device inventory found. Run the enhanced device inventory script first." -ForegroundColor Red
        return $null
    }
}

function Deploy-RemoteAccessSoftware {
    param($DeviceName)
    
    Write-Host "`n=== DEPLOYING REMOTE ACCESS TO $DeviceName ===" -ForegroundColor Cyan
    
    # This would require DeviceManagementManagedDevices.PrivilegedOperations.All permission
    try {
        # Get the device
        $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'"
        
        if ($device) {
            Write-Host "✅ Found device: $($device.DeviceName)" -ForegroundColor Green
            
            # Create a PowerShell script to enable RDP and install remote software
            $scriptContent = @"
# Enable RDP
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Download and install TeamViewer Quick Support (portable)
`$teamViewerUrl = "https://download.teamviewer.com/download/TeamViewerQS.exe"
`$tempPath = "`$env:TEMP\TeamViewerQS.exe"
Invoke-WebRequest -Uri `$teamViewerUrl -OutFile `$tempPath
Start-Process `$tempPath

Write-Host "RDP enabled and TeamViewer QuickSupport downloaded to `$tempPath"
"@
            
            # Deploy the script (this requires additional permissions)
            Write-Host "📋 Script ready for deployment:" -ForegroundColor Yellow
            Write-Host $scriptContent -ForegroundColor Gray
            
            # Note: Actual script deployment would require DeviceManagementManagedDevices.PrivilegedOperations.All
            Write-Host "`n⚠️  To deploy this script, you need to add the following permission:" -ForegroundColor Yellow
            Write-Host "   DeviceManagementManagedDevices.PrivilegedOperations.All" -ForegroundColor Cyan
            
        } else {
            Write-Host "❌ Device not found in Intune" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Error deploying remote access: $($_.Exception.Message)" -ForegroundColor Red
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    if ($ListCandidates) {
        $candidates = Get-RemoteAccessCandidates
        
        Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
        Write-Host "1. Add required permissions for remote operations:" -ForegroundColor Yellow
        Write-Host "   - DeviceManagementManagedDevices.PrivilegedOperations.All" -ForegroundColor Cyan
        Write-Host "2. Target the top candidates for remote access deployment" -ForegroundColor Yellow
        Write-Host "3. Use: .\Deploy-RemoteAccess.ps1 -TargetDevice 'DEVICE_NAME' -DeployTeamViewer" -ForegroundColor Yellow
    }
    
    if ($TargetDevice -and $DeployTeamViewer) {
        Deploy-RemoteAccessSoftware -DeviceName $TargetDevice
    }
    
} catch {
    Write-Error "Failed to deploy remote access: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}