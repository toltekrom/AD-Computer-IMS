#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

param(
    [string]$ConfigPath = "E:\Users\jerom\source\AD-Computer-IMS\config\appsettings.json"
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Find-SteppingStoneDevice {
    param([string]$TargetDeviceName)
    
    Write-Host "`n=== SEARCHING FOR STEPPING STONE DEVICE ===" -ForegroundColor Cyan
    Write-Host "Target Device: $TargetDeviceName" -ForegroundColor Yellow
    
    # Check your device inventory first
    $inventoryPath = "E:\Users\jerom\source\AD-Computer-IMS\output"
    $latestInventory = Get-ChildItem -Path $inventoryPath -Filter "DeviceInventory_Enhanced_*.csv" | 
        Sort-Object CreationTime -Descending | Select-Object -First 1
    
    if ($latestInventory) {
        Write-Host "Checking inventory: $($latestInventory.Name)" -ForegroundColor Gray
        $devices = Import-Csv $latestInventory.FullName
        
        # Look for the specific device
        $targetDevice = $devices | Where-Object { $_.DeviceName -like "*$TargetDeviceName*" }
        
        if ($targetDevice) {
            Write-Host "`n🎯 FOUND TARGET DEVICE IN INVENTORY:" -ForegroundColor Green
            foreach ($device in $targetDevice) {
                Write-Host "`n📱 Device: $($device.DeviceName)" -ForegroundColor White
                Write-Host "   Primary User: $($device.PrimaryUser)" -ForegroundColor Gray
                Write-Host "   Last Activity: $($device.LastSignIn)" -ForegroundColor Gray
                Write-Host "   OS: $($device.OperatingSystem)" -ForegroundColor Gray
                Write-Host "   Managed: $($device.IsManaged)" -ForegroundColor Gray
                Write-Host "   Compliant: $($device.IsCompliant)" -ForegroundColor Gray
                Write-Host "   Management Agent: $($device.ManagementAgent)" -ForegroundColor Gray
                Write-Host "   Special Notes: $($device.SpecialNotes)" -ForegroundColor Cyan
                
                # Analyze connectivity potential
                if ($device.IsManaged -eq "True" -and $device.IsCompliant -eq "True") {
                    Write-Host "   ✅ EXCELLENT TARGET - Managed & Compliant" -ForegroundColor Green
                } elseif ($device.IsManaged -eq "True") {
                    Write-Host "   ⚠️  GOOD TARGET - Managed but compliance unknown" -ForegroundColor Yellow
                } else {
                    Write-Host "   ❌ LIMITED TARGET - Not Intune managed" -ForegroundColor Red
                }
            }
            
            return $targetDevice
        } else {
            Write-Host "❌ Device not found in current inventory" -ForegroundColor Red
        }
    }
    
    # Try to find it in Azure AD directly
    Write-Host "`n🔍 SEARCHING AZURE AD FOR DEVICE..." -ForegroundColor Cyan
    try {
        $azureDevices = Get-MgDevice -Filter "displayName eq '$TargetDeviceName'" -ErrorAction SilentlyContinue
        
        if (-not $azureDevices) {
            # Try partial match
            $azureDevices = Get-MgDevice -All | Where-Object { $_.DisplayName -like "*$TargetDeviceName*" }
        }
        
        if ($azureDevices) {
            Write-Host "✅ Found in Azure AD!" -ForegroundColor Green
            foreach ($device in $azureDevices) {
                Write-Host "`n📱 Azure Device: $($device.DisplayName)" -ForegroundColor White
                Write-Host "   Device ID: $($device.DeviceId)" -ForegroundColor Gray
                Write-Host "   OS: $($device.OperatingSystem)" -ForegroundColor Gray
                Write-Host "   Last Sign-In: $($device.ApproximateLastSignInDateTime)" -ForegroundColor Gray
                Write-Host "   Trust Type: $($device.TrustType)" -ForegroundColor Gray
                Write-Host "   Managed: $($device.IsManaged)" -ForegroundColor Gray
            }
            return $azureDevices
        } else {
            Write-Host "❌ Device not found in Azure AD either" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Error searching Azure AD: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    return $null
}

function Get-NetworkNeighborAnalysis {
    Write-Host "`n=== NETWORK NEIGHBOR ANALYSIS ===" -ForegroundColor Cyan
    Write-Host "Since desktop-tn5mjd9 can reach PCWAD1, let's find similar devices:" -ForegroundColor Yellow
    
    $inventoryPath = "E:\Users\jerom\source\AD-Computer-IMS\output"
    $latestInventory = Get-ChildItem -Path $inventoryPath -Filter "DeviceInventory_Enhanced_*.csv" | 
        Sort-Object CreationTime -Descending | Select-Object -First 1
    
    if ($latestInventory) {
        $devices = Import-Csv $latestInventory.FullName
        
        # Look for devices with similar naming patterns (likely same network)
        $potentialNeighbors = $devices | Where-Object {
            $_.DeviceName -like "desktop-*" -or
            $_.DeviceName -like "PCWA*" -or
            $_.LocationHint -eq "PCWA" -or
            ($_.LastSignIn -and [DateTime]$_.LastSignIn -gt (Get-Date).AddDays(-7))
        } | Sort-Object LastSignIn -Descending
        
        Write-Host "`n🌐 POTENTIAL NETWORK NEIGHBORS:" -ForegroundColor Yellow
        foreach ($device in $potentialNeighbors | Select-Object -First 10) {
            Write-Host "`n📱 $($device.DeviceName)" -ForegroundColor White
            Write-Host "   User: $($device.PrimaryUser)" -ForegroundColor Gray
            Write-Host "   Last Active: $($device.LastSignIn)" -ForegroundColor Gray
            Write-Host "   Managed: $($device.IsManaged)" -ForegroundColor Gray
            
            if ($device.DeviceName -like "desktop-*") {
                Write-Host "   🎯 SAME NAMING PATTERN - Likely same network!" -ForegroundColor Green
            }
        }
        
        return $potentialNeighbors
    }
    
    return $null
}

function Create-SteppingStoneStrategy {
    param($TargetDevice, $NetworkNeighbors)
    
    Write-Host "`n=== STEPPING STONE STRATEGY ===" -ForegroundColor Cyan
    
    if ($TargetDevice) {
        Write-Host "🎯 PRIMARY TARGET: desktop-tn5mjd9" -ForegroundColor Yellow
        Write-Host "   Strategy: Get remote access to this device" -ForegroundColor White
        Write-Host "   Why: It can already communicate with PCWAD1" -ForegroundColor White
        Write-Host "   Then: Use it as a jumping point to reach 192.168.102.230" -ForegroundColor White
        
        if ($TargetDevice.IsManaged -eq "True") {
            Write-Host "`n✅ INTUNE DEPLOYMENT APPROACH:" -ForegroundColor Green
            Write-Host "1. Deploy remote access tools via Intune to desktop-tn5mjd9" -ForegroundColor White
            Write-Host "2. Enable RDP on the device" -ForegroundColor White
            Write-Host "3. Install TeamViewer or use Quick Assist" -ForegroundColor White
            Write-Host "4. Once connected, use desktop-tn5mjd9 to reach PCWAD1" -ForegroundColor White
        } else {
            Write-Host "`n⚠️  MANUAL APPROACH REQUIRED:" -ForegroundColor Yellow
            Write-Host "1. Contact the user of desktop-tn5mjd9" -ForegroundColor White
            Write-Host "2. Ask them to install TeamViewer or enable RDP" -ForegroundColor White
            Write-Host "3. Get them to provide access credentials" -ForegroundColor White
        }
    }
    
    if ($NetworkNeighbors -and $NetworkNeighbors.Count -gt 0) {
        Write-Host "`n🌐 BACKUP TARGETS:" -ForegroundColor Yellow
        $managedNeighbors = $NetworkNeighbors | Where-Object { $_.IsManaged -eq "True" } | Select-Object -First 3
        
        foreach ($neighbor in $managedNeighbors) {
            Write-Host "   📱 $($neighbor.DeviceName) - User: $($neighbor.PrimaryUser)" -ForegroundColor White
        }
        
        Write-Host "`n💡 NETWORK INSIGHT:" -ForegroundColor Cyan
        Write-Host "These devices likely share the same network segment as desktop-tn5mjd9" -ForegroundColor Gray
        Write-Host "If one can reach PCWAD1, others probably can too!" -ForegroundColor Gray
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Search for the stepping stone device
    $steppingStone = Find-SteppingStoneDevice -TargetDeviceName "desktop-tn5mjd9"
    
    # Analyze potential network neighbors
    $neighbors = Get-NetworkNeighborAnalysis
    
    # Create strategy
    Create-SteppingStoneStrategy -TargetDevice $steppingStone -NetworkNeighbors $neighbors
    
    Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Run this analysis to find desktop-tn5mjd9 in your inventory" -ForegroundColor Yellow
    Write-Host "2. If found and managed, deploy remote access tools to it" -ForegroundColor Yellow
    Write-Host "3. Use desktop-tn5mjd9 as a stepping stone to reach PCWAD1" -ForegroundColor Yellow
    Write-Host "4. Consider the backup targets if primary approach fails" -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to analyze stepping stone device: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}