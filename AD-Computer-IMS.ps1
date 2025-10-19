#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Reports

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\appsettings.json"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "output"),
    [switch]$ExportToCsv,
    [switch]$ReturnJson,
    [switch]$DetectiveMode,
    [switch]$IncludeAuditLogs
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Get-DeviceNetworkContext {
    param($device, $managedDevice)
    
    # Try to determine if device is on LAN or WAN based on various indicators
    $networkContext = [PSCustomObject]@{
        NetworkType = "Unknown"
        LastKnownIP = "Unknown"
        IsVPNCapable = $false
        NetworkConfidence = "Low"
        NetworkIndicators = @()
    }
    
    try {
        # Check if we can get network info from Intune device
        if ($managedDevice) {
            # Get device configuration profiles that might indicate VPN
            $deviceConfigs = Get-MgDeviceManagementManagedDeviceConfiguration -ManagedDeviceId $managedDevice.Id -ErrorAction SilentlyContinue
            
            if ($deviceConfigs) {
                $vpnConfigs = $deviceConfigs | Where-Object { $_.DisplayName -like "*VPN*" -or $_.DisplayName -like "*Remote*" }
                if ($vpnConfigs) {
                    $networkContext.IsVPNCapable = $true
                    $networkContext.NetworkIndicators += "VPN-Configured"
                }
            }
            
            # Check compliance policies for network requirements
            $compliancePolicies = Get-MgDeviceManagementManagedDeviceDeviceCompliancePolicyState -ManagedDeviceId $managedDevice.Id -ErrorAction SilentlyContinue
            
            # Analyze device name patterns for location hints
            if ($device.DisplayName -match '^(PCWA|BUCKHORN)') {
                $networkContext.NetworkType = "Corporate-LAN"
                $networkContext.NetworkConfidence = "High"
                $networkContext.NetworkIndicators += "Corporate-Naming-Pattern"
            }
            elseif ($device.DisplayName -match '^(LAPTOP|SURFACE|MOBILE)' -or $device.DeviceOwnership -eq "Personal") {
                $networkContext.NetworkType = "Remote-WAN"
                $networkContext.NetworkConfidence = "Medium"
                $networkContext.NetworkIndicators += "Mobile-Device-Pattern"
            }
            elseif ($device.DisplayName -match '^(DESKTOP|WORKSTATION)') {
                $networkContext.NetworkType = "Corporate-LAN"
                $networkContext.NetworkConfidence = "Medium"
                $networkContext.NetworkIndicators += "Desktop-Pattern"
            }
            
            # Check join type for additional context
            if ($managedDevice.JoinType -eq "azureADJoined") {
                $networkContext.NetworkIndicators += "Cloud-Joined"
            }
            elseif ($managedDevice.JoinType -eq "hybridAzureADJoined") {
                $networkContext.NetworkIndicators += "Hybrid-Joined"
                # Hybrid joined devices often indicate on-premise presence
                if ($networkContext.NetworkType -eq "Unknown") {
                    $networkContext.NetworkType = "Corporate-LAN"
                    $networkContext.NetworkConfidence = "Medium"
                }
            }
        }
        
    } catch {
        Write-Verbose "Could not retrieve network context for $($device.DisplayName): $($_.Exception.Message)"
    }
    
    return $networkContext
}

function Get-ActualLastUser {
    param($device, $managedDevice)
    
    $lastUserInfo = [PSCustomObject]@{
        ActualLastUser = "Unknown"
        LastUserLoginTime = $null
        DataSource = "None"
        Confidence = "Low"
        Notes = @()
    }
    
    try {
        # Method 1: Try to get sign-in logs for this device (requires AuditLog.Read.All)
        if ($IncludeAuditLogs) {
            try {
                $signInLogs = Get-MgAuditLogSignIn -Filter "deviceDetail/deviceId eq '$($device.DeviceId)'" -Top 1 -OrderBy "createdDateTime desc" -ErrorAction SilentlyContinue
                
                if ($signInLogs) {
                    $lastUserInfo.ActualLastUser = $signInLogs[0].UserPrincipalName
                    $lastUserInfo.LastUserLoginTime = $signInLogs[0].CreatedDateTime
                    $lastUserInfo.DataSource = "SignInLogs"
                    $lastUserInfo.Confidence = "High"
                    $lastUserInfo.Notes += "Real sign-in event from audit logs"
                }
            } catch {
                $lastUserInfo.Notes += "Sign-in logs not accessible (need AuditLog.Read.All permission)"
            }
        }
        
        # Method 2: Try to get device usage from Intune
        if ($managedDevice -and $lastUserInfo.ActualLastUser -eq "Unknown") {
            try {
                # Get device users from Intune
                $deviceUsers = Get-MgDeviceManagementManagedDeviceUser -ManagedDeviceId $managedDevice.Id -ErrorAction SilentlyContinue
                
                if ($deviceUsers) {
                    # Sort by last activity if available
                    $mostRecentUser = $deviceUsers | Sort-Object LastLogOnDateTime -Descending | Select-Object -First 1
                    
                    if ($mostRecentUser) {
                        $lastUserInfo.ActualLastUser = $mostRecentUser.DisplayName
                        $lastUserInfo.LastUserLoginTime = $mostRecentUser.LastLogOnDateTime
                        $lastUserInfo.DataSource = "IntuneDeviceUsers"
                        $lastUserInfo.Confidence = "Medium"
                        $lastUserInfo.Notes += "From Intune device user tracking"
                    }
                }
            } catch {
                $lastUserInfo.Notes += "Intune device users not accessible"
            }
        }
        
        # Method 3: Fallback to primary user but flag it clearly
        if ($lastUserInfo.ActualLastUser -eq "Unknown" -and $managedDevice) {
            if ($managedDevice.UserId) {
                $user = Get-MgUser -UserId $managedDevice.UserId -ErrorAction SilentlyContinue
                if ($user) {
                    $lastUserInfo.ActualLastUser = $user.UserPrincipalName
                    $lastUserInfo.DataSource = "PrimaryUserFallback"
                    $lastUserInfo.Confidence = "Low"
                    $lastUserInfo.Notes += "⚠️ Primary user only - not actual last login"
                }
            }
        }
        
        # Method 4: Check if the user is still active in the organization
        if ($lastUserInfo.ActualLastUser -ne "Unknown") {
            try {
                $userCheck = Get-MgUser -UserId $lastUserInfo.ActualLastUser -ErrorAction SilentlyContinue
                if (-not $userCheck) {
                    $lastUserInfo.Notes += "❌ User no longer exists in organization"
                } elseif ($userCheck.AccountEnabled -eq $false) {
                    $lastUserInfo.Notes += "❌ User account is disabled"
                }
            } catch {
                $lastUserInfo.Notes += "❌ Could not verify user status"
            }
        }
        
    } catch {
        $lastUserInfo.Notes += "Error retrieving user info: $($_.Exception.Message)"
    }
    
    return $lastUserInfo
}

function Get-NetworkInsights {
    param($devices)
    
    Write-Host "`n=== NETWORK RECONNAISSANCE ===" -ForegroundColor Cyan
    
    # Analyze network distribution
    $lanDevices = $devices | Where-Object { $_.NetworkType -eq "Corporate-LAN" }
    $wanDevices = $devices | Where-Object { $_.NetworkType -eq "Remote-WAN" }
    $unknownDevices = $devices | Where-Object { $_.NetworkType -eq "Unknown" }
    
    Write-Host "`n📊 NETWORK DISTRIBUTION:" -ForegroundColor Yellow
    Write-Host "  🏢 Corporate LAN: $($lanDevices.Count) devices" -ForegroundColor Green
    Write-Host "  🌐 Remote WAN: $($wanDevices.Count) devices" -ForegroundColor Blue
    Write-Host "  ❓ Unknown: $($unknownDevices.Count) devices" -ForegroundColor Gray
    
    # Show suspicious last user entries
    $suspiciousDevices = $devices | Where-Object { 
        $_.LastUserNotes -like "*no longer exists*" -or 
        $_.LastUserNotes -like "*disabled*" -or
        $_.LastUserConfidence -eq "Low"
    }
    
    if ($suspiciousDevices) {
        Write-Host "`n⚠️  SUSPICIOUS LAST USER DATA:" -ForegroundColor Red
        $suspiciousDevices | ForEach-Object {
            Write-Host "  📱 $($_.DeviceName)" -ForegroundColor White
            Write-Host "    Last User: $($_.ActualLastUser) (Confidence: $($_.LastUserConfidence))" -ForegroundColor Yellow
            Write-Host "    Notes: $($_.LastUserNotes)" -ForegroundColor Gray
            Write-Host "    Network: $($_.NetworkType)" -ForegroundColor Cyan
        }
    }
    
    # Group by potential office locations
    $locationGroups = $devices | Group-Object { 
        if ($_.DeviceName -match '^[A-Z]{2,4}[-_]') {
            ($_.DeviceName -split '[-_]')[0]
        } else {
            "Unknown"
        }
    }
    
    Write-Host "`n🏢 POTENTIAL OFFICE LOCATIONS/NETWORKS:" -ForegroundColor Yellow
    foreach ($group in $locationGroups) {
        $lanCount = ($group.Group | Where-Object { $_.NetworkType -eq "Corporate-LAN" }).Count
        $wanCount = ($group.Group | Where-Object { $_.NetworkType -eq "Remote-WAN" }).Count
        
        Write-Host "  $($group.Name): $($group.Count) devices (LAN: $lanCount, WAN: $wanCount)" -ForegroundColor White
        $group.Group | Select-Object -First 3 DeviceName, ActualLastUser, NetworkType | 
            ForEach-Object { Write-Host "    - $($_.DeviceName) (Last: $($_.ActualLastUser), Net: $($_.NetworkType))" -ForegroundColor Gray }
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Check what permissions we have
    $context = Get-MgContext
    Write-Host "Current scopes: $($context.Scopes -join ', ')" -ForegroundColor Gray
    
    if ($IncludeAuditLogs -and $context.Scopes -notcontains "AuditLog.Read.All") {
        Write-Host "⚠️  AuditLog.Read.All permission not granted - will use fallback methods for last user" -ForegroundColor Yellow
    }
    
    # Get devices with enhanced properties
    $devices = Get-MgDevice -All -Property "Id,DisplayName,OperatingSystem,OperatingSystemVersion,LastSignInDateTime,ApproximateLastSignInDateTime,DeviceId,IsCompliant,IsManaged,TrustType,ProfileType,SystemLabels,DeviceOwnership"
    
    $result = @()
    $total = $devices.Count
    $count = 0
    
    Write-Host "Processing $total devices with network analysis and real last user detection..." -ForegroundColor Yellow
    
    foreach ($device in $devices) {
        $count++
        Write-Progress -Activity "Processing devices..." -Status "Processing $($device.DisplayName) ($count of $total)" -PercentComplete (($count / $total) * 100)
        
        $managedDevice = $null
        $primaryUser = $null
        
        if ($device.IsManaged) {
            try {
                $managedDevice = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$($device.DeviceId)'" -ErrorAction SilentlyContinue
                
                if ($managedDevice -and $managedDevice.UserId) {
                    $user = Get-MgUser -UserId $managedDevice.UserId -ErrorAction SilentlyContinue
                    $primaryUser = $user.UserPrincipalName
                }
            }
            catch {
                Write-Verbose "Could not retrieve managed device info for $($device.DisplayName)"
            }
        }
        
        # Get network context
        $networkContext = Get-DeviceNetworkContext -device $device -managedDevice $managedDevice
        
        # Get actual last user information
        $lastUserInfo = Get-ActualLastUser -device $device -managedDevice $managedDevice
        
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
        if ($lastUserInfo.Notes -contains "❌ User no longer exists in organization") { $specialNotes += "Orphaned Device - User Gone" }
        
        $result += [PSCustomObject]@{
            DeviceName = $device.DisplayName
            DeviceId = $device.DeviceId
            OperatingSystem = $device.OperatingSystem
            OSVersion = $device.OperatingSystemVersion
            DeviceLastSeen = $device.LastSignInDateTime ?? $device.ApproximateLastSignInDateTime
            IsCompliant = $device.IsCompliant
            IsManaged = $device.IsManaged
            TrustType = $device.TrustType
            DeviceOwnership = $device.DeviceOwnership
            PrimaryUser = $primaryUser
            ActualLastUser = $lastUserInfo.ActualLastUser
            LastUserLoginTime = $lastUserInfo.LastUserLoginTime
            LastUserDataSource = $lastUserInfo.DataSource
            LastUserConfidence = $lastUserInfo.Confidence
            LastUserNotes = ($lastUserInfo.Notes -join "; ")
            NetworkType = $networkContext.NetworkType
            NetworkConfidence = $networkContext.NetworkConfidence
            NetworkIndicators = ($networkContext.NetworkIndicators -join "; ")
            IsVPNCapable = $networkContext.IsVPNCapable
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
        
        Write-Host "`n=== DATA QUALITY INSIGHTS ===" -ForegroundColor Cyan
        $highConfidenceUsers = $result | Where-Object { $_.LastUserConfidence -eq "High" }
        $lowConfidenceUsers = $result | Where-Object { $_.LastUserConfidence -eq "Low" }
        
        Write-Host "✅ High Confidence Last User Data: $($highConfidenceUsers.Count) devices" -ForegroundColor Green
        Write-Host "⚠️  Low Confidence Last User Data: $($lowConfidenceUsers.Count) devices" -ForegroundColor Yellow
        Write-Host "💡 Consider running with -IncludeAuditLogs for better last user accuracy" -ForegroundColor Cyan
    }
    
    # Export with all enhanced columns
    if ($ExportToCsv) {
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        $csvPath = Join-Path $OutputPath "DeviceInventory_NetworkEnhanced_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $result | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "`nNetwork-enhanced results exported to: $csvPath" -ForegroundColor Green
        Write-Host "✅ New columns: NetworkType, ActualLastUser, LastUserConfidence, NetworkIndicators" -ForegroundColor Green
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