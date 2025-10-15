#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\appsettings.json"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "output"),
    [switch]$ExportToCsv,
    [switch]$ReturnJson,
    [switch]$DetectiveMode
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Get-NetworkInsights {
    param($devices)
    
    Write-Host "`n=== NETWORK RECONNAISSANCE ===" -ForegroundColor Cyan
    
    # Group by potential office locations (based on device naming patterns)
    $locationGroups = $devices | Group-Object { 
        if ($_.DeviceName -match '^[A-Z]{2,4}[-_]') {
            ($_.DeviceName -split '[-_]')[0]
        } else {
            "Unknown"
        }
    }
    
    Write-Host "`nPotential Office Locations/Networks:" -ForegroundColor Yellow
    foreach ($group in $locationGroups) {
        Write-Host "  $($group.Name): $($group.Count) devices" -ForegroundColor White
        $group.Group | Select-Object -First 3 DeviceName, PrimaryUser | 
            ForEach-Object { Write-Host "    - $($_.DeviceName) (Primary: $($_.PrimaryUser))" -ForegroundColor Gray }
    }
    
    # Identify server-like devices and infrastructure
    $serverCandidates = $devices | Where-Object {
        $_.DeviceName -match "(server|srv|dc|sql|file|print|admin|gateway|jump)" -or
        $_.OperatingSystem -match "Server" -or
        $_.DeviceName -like "*ADMIN*" -or
        $_.DeviceName -like "*PCWA*"
    }
    
    if ($serverCandidates) {
        Write-Host "`n🖥️ INFRASTRUCTURE DEVICES FOUND:" -ForegroundColor Yellow
        $serverCandidates | ForEach-Object {
            $lastActivity = $_.LastSignIn ?? $_.LastSyncDateTime ?? "Never"
            Write-Host "  🔍 $($_.DeviceName)" -ForegroundColor White
            Write-Host "    OS: $($_.OperatingSystem)" -ForegroundColor Gray
            Write-Host "    Primary User: $($_.PrimaryUser)" -ForegroundColor Gray
            Write-Host "    Last Activity: $lastActivity" -ForegroundColor Gray
            Write-Host "    Managed: $($_.IsManaged) | Compliant: $($_.IsCompliant)" -ForegroundColor Gray
            if ($_.DeviceName -like "*ADMIN*") {
                Write-Host "    ⚠️  POTENTIAL JUMPBOX/GATEWAY!" -ForegroundColor Red
            }
            Write-Host ""
        }
    }
    
    # Identify devices with previous IT admin as primary user
    $previousITDevices = $devices | Where-Object { 
        $_.PrimaryUser -ne $null -and 
        $_.PrimaryUser -match "(admin|it\.)" 
    }
    
    if ($previousITDevices) {
        Write-Host "`n👤 DEVICES WITH PREVIOUS IT ADMIN AS PRIMARY:" -ForegroundColor Yellow
        $previousITDevices | ForEach-Object {
            Write-Host "  - $($_.DeviceName) (Primary: $($_.PrimaryUser))" -ForegroundColor Red
        }
        Write-Host "  💡 These may need user reassignment!" -ForegroundColor Gray
    }
    
    # Identify remote access candidates
    $remoteAccessCandidates = $devices | Where-Object {
        $_.IsManaged -eq $true -and 
        $_.IsCompliant -eq $true -and
        $_.RemoteAccessReady -eq "Yes" -and
        $_.PrimaryUser -ne $null -and
        $_.PrimaryUser -notmatch "(admin|it\.)"
    }
    
    Write-Host "`n🔗 BEST REMOTE ACCESS CANDIDATES:" -ForegroundColor Yellow
    if ($remoteAccessCandidates) {
        $remoteAccessCandidates | Select-Object -First 5 DeviceName, PrimaryUser, LastSignIn, RemoteAccessReady |
            ForEach-Object { 
                Write-Host "  ✅ $($_.DeviceName) (Primary: $($_.PrimaryUser), Last Activity: $($_.LastSignIn))" -ForegroundColor Green 
            }
    } else {
        Write-Host "  ⚠️  No ideal candidates found - may need to work with IT admin devices" -ForegroundColor Yellow
    }
}

function Get-UserInsights {
    param($devices)
    
    Write-Host "`n=== USER ANALYSIS ===" -ForegroundColor Cyan
    
    # Active users by location
    $activeUsers = $devices | Where-Object { 
        $_.PrimaryUser -ne $null -and 
        ($_.LastSignIn -gt (Get-Date).AddDays(-14) -or $_.LastSyncDateTime -gt (Get-Date).AddDays(-14))
    }
    
    $usersByLocation = $activeUsers | Group-Object { 
        if ($_.DeviceName -match '^[A-Z]{2,4}[-_]') {
            ($_.DeviceName -split '[-_]')[0]
        } else {
            "Remote/Unknown"
        }
    }
    
    Write-Host "`nActive Users by Location:" -ForegroundColor Yellow
    foreach ($group in $usersByLocation) {
        Write-Host "  $($group.Name):" -ForegroundColor White
        $uniqueUsers = $group.Group | Select-Object -Unique PrimaryUser
        $uniqueUsers | ForEach-Object { 
            Write-Host "    - $($_.PrimaryUser)" -ForegroundColor Gray 
        }
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Get devices with enhanced properties
    $devices = Get-MgDevice -All -Property "Id,DisplayName,OperatingSystem,OperatingSystemVersion,LastSignInDateTime,ApproximateLastSignInDateTime,DeviceId,IsCompliant,IsManaged,TrustType,ProfileType,SystemLabels,DeviceOwnership"
    
    $result = @()
    $total = $devices.Count
    $count = 0
    
    Write-Host "Processing $total devices with enhanced user tracking..." -ForegroundColor Yellow
    
    foreach ($device in $devices) {
        $count++
        Write-Progress -Activity "Processing devices..." -Status "Processing $($device.DisplayName) ($count of $total)" -PercentComplete (($count / $total) * 100)
        
        $managedDevice = $null
        $primaryUser = $null
        $lastSignInUser = $null
        
        if ($device.IsManaged) {
            try {
                $managedDevice = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$($device.DeviceId)'" -ErrorAction SilentlyContinue
                
                if ($managedDevice) {
                    # Get primary user (assigned user)
                    if ($managedDevice.UserId) {
                        $user = Get-MgUser -UserId $managedDevice.UserId -ErrorAction SilentlyContinue
                        $primaryUser = $user.UserPrincipalName
                    }
                    
                    # Try to get last signed-in user (this might be different from primary)
                    # Note: This information might not always be available through Graph API
                    $lastSignInUser = $managedDevice.UserDisplayName ?? $primaryUser
                }
            }
            catch {
                Write-Verbose "Could not retrieve managed device info for $($device.DisplayName)"
            }
        }
        
        # Determine remote access readiness
        $isRecentlyActive = ($device.LastSignInDateTime -and $device.LastSignInDateTime -gt (Get-Date).AddDays(-7)) -or 
                           ($device.ApproximateLastSignInDateTime -and $device.ApproximateLastSignInDateTime -gt (Get-Date).AddDays(-7)) -or
                           ($managedDevice -and $managedDevice.LastSyncDateTime -and $managedDevice.LastSyncDateTime -gt (Get-Date).AddDays(-7))
        
        $remoteAccessReady = if ($device.IsManaged -and $device.IsCompliant -and $isRecentlyActive -and $primaryUser) { "Yes" } else { "No" }
        
        # Enhanced device analysis
        $locationHint = if ($device.DisplayName -match '^[A-Z]{2,4}[-_]') { 
            ($device.DisplayName -split '[-_]')[0] 
        } else { 
            "Unknown" 
        }
        
        $serverLikelihood = if ($device.DisplayName -match "(server|srv|dc|sql|file|print|admin|gateway|jump)" -or 
                               $device.OperatingSystem -match "Server" -or 
                               $device.DisplayName -like "*ADMIN*") { 
            "High" 
        } else { 
            "Low" 
        }
        
        # Special flagging for interesting devices
        $specialNotes = @()
        if ($device.DisplayName -like "*ADMIN*") { $specialNotes += "Potential Jumpbox/Gateway" }
        if ($device.DisplayName -like "*PCWA*") { $specialNotes += "PCWA Infrastructure" }
        if ($primaryUser -and $primaryUser -match "(admin|it\.)") { $specialNotes += "Previous IT Admin Device" }
        
        $result += [PSCustomObject]@{
            DeviceName = $device.DisplayName
            DeviceId = $device.DeviceId
            OperatingSystem = $device.OperatingSystem
            OSVersion = $device.OperatingSystemVersion
            LastSignIn = $device.LastSignInDateTime ?? $device.ApproximateLastSignInDateTime
            IsCompliant = $device.IsCompliant
            IsManaged = $device.IsManaged
            TrustType = $device.TrustType
            DeviceOwnership = $device.DeviceOwnership
            PrimaryUser = $primaryUser
            LastSignInUser = $lastSignInUser
            SerialNumber = $managedDevice.SerialNumber
            Model = $managedDevice.Model
            Manufacturer = $managedDevice.Manufacturer
            ComplianceState = $managedDevice.ComplianceState
            JoinType = $managedDevice.JoinType
            ManagementAgent = $managedDevice.ManagementAgent
            LastSyncDateTime = $managedDevice.LastSyncDateTime
            LocationHint = $locationHint
            ServerLikelihood = $serverLikelihood
            RemoteAccessReady = $remoteAccessReady
            SpecialNotes = ($specialNotes -join "; ")
            QueryTimestamp = Get-Date
        }
    }
    
    Write-Progress -Activity "Processing devices..." -Completed
    
    # Detective mode analysis
    if ($DetectiveMode) {
        Get-NetworkInsights -devices $result
        Get-UserInsights -devices $result
        
        Write-Host "`n=== BUCKHORN INFRASTRUCTURE INSIGHTS ===" -ForegroundColor Cyan
        Write-Host "🔍 PCWAD1 (192.168.102.230) - On-premise Domain Controller" -ForegroundColor Yellow
        Write-Host "🔍 BUCKHORN_ADMIN - Likely jumpbox/gateway for remote access" -ForegroundColor Yellow
        Write-Host "🔍 Multiple PCWA devices found - part of hybrid infrastructure" -ForegroundColor Yellow
        
        Write-Host "`n=== REMOTE ACCESS STRATEGY ===" -ForegroundColor Cyan
        Write-Host "1. Target BUCKHORN_ADMIN device if it's accessible and managed" -ForegroundColor Yellow
        Write-Host "2. Use devices marked 'RemoteAccessReady = Yes' for software deployment" -ForegroundColor Yellow
        Write-Host "3. Reassign devices with previous IT admin as primary user" -ForegroundColor Yellow
        Write-Host "4. Try connecting to 192.168.102.230 (PCWAD1) if you can reach the network" -ForegroundColor Yellow
    }
    
    # Export with all enhanced columns
    if ($ExportToCsv) {
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        $csvPath = Join-Path $OutputPath "DeviceInventory_Enhanced_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $result | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "`nEnhanced results exported to: $csvPath" -ForegroundColor Green
        Write-Host "✅ Now includes: RemoteAccessReady, LastSignInUser, SpecialNotes columns" -ForegroundColor Green
    }
    
    if ($ReturnJson) {
        return ($result | ConvertTo-Json -Depth 3)
    }
    
    return $result
    
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    throw
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}