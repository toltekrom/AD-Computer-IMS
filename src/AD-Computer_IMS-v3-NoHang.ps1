#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\appsettings.json"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "output"),
    [switch]$ExportToCsv,
    [switch]$ReturnJson,
    [switch]$DetectiveMode,
    [int]$TimeoutSeconds = 30
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Get-DeviceInfoWithTimeout {
    param(
        $Device,
        [int]$TimeoutSeconds = 30
    )
    
    $job = Start-Job -ScriptBlock {
        param($DeviceId, $ClientId, $TenantId, $Thumbprint)
        
        # Import modules in job
        Import-Module Microsoft.Graph.Authentication -Force
        Import-Module Microsoft.Graph.DeviceManagement -Force
        
        # Connect in job context
        Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -CertificateThumbprint $Thumbprint -NoWelcome
        
        try {
            # Get managed device info
            $managedDevice = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$DeviceId'" -ErrorAction Stop
            
            $primaryUser = $null
            if ($managedDevice -and $managedDevice.UserId) {
                $user = Get-MgUser -UserId $managedDevice.UserId -ErrorAction Stop
                $primaryUser = $user.UserPrincipalName
            }
            
            return @{
                ManagedDevice = $managedDevice
                PrimaryUser = $primaryUser
                Success = $true
            }
        }
        catch {
            return @{
                Error = $_.Exception.Message
                Success = $false
            }
        }
        finally {
            Disconnect-MgGraph -ErrorAction SilentlyContinue
        }
    } -ArgumentList $Device.DeviceId, $clientId, $tenantId, $thumbprint
    
    # Wait for job with timeout
    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    
    if ($completed) {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job
        return $result
    } else {
        Write-Warning "Timeout getting device info for $($Device.DisplayName) - stopping job"
        Stop-Job -Job $job
        Remove-Job -Job $job
        return @{ Success = $false; Error = "Timeout after $TimeoutSeconds seconds" }
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Get all devices
    Write-Host "Querying devices from Microsoft Graph..." -ForegroundColor Yellow
    $devices = Get-MgDevice -All -Property "Id,DisplayName,OperatingSystem,OperatingSystemVersion,LastSignInDateTime,ApproximateLastSignInDateTime,DeviceId,IsCompliant,IsManaged,TrustType,ProfileType,SystemLabels,DeviceOwnership"
    
    $result = @()
    $total = $devices.Count
    $count = 0
    $skippedDevices = @()
    
    Write-Host "Processing $total devices with timeout protection..." -ForegroundColor Yellow
    
    foreach ($device in $devices) {
        $count++
        $percentComplete = [math]::Round(($count / $total) * 100, 1)
        Write-Progress -Activity "Processing devices with timeout..." -Status "Processing $($device.DisplayName) ($count of $total) - $percentComplete%" -PercentComplete $percentComplete
        
        Write-Host "Processing device $count/$total : $($device.DisplayName)" -ForegroundColor Cyan
        
        # Basic device info (always available)
        $deviceInfo = [PSCustomObject]@{
            DeviceName = $device.DisplayName
            DeviceId = $device.DeviceId
            OperatingSystem = $device.OperatingSystem
            OSVersion = $device.OperatingSystemVersion
            LastSignIn = $device.LastSignInDateTime ?? $device.ApproximateLastSignInDateTime
            IsCompliant = $device.IsCompliant
            IsManaged = $device.IsManaged
            TrustType = $device.TrustType
            DeviceOwnership = $device.DeviceOwnership
            LocationHint = if ($device.DisplayName -match '^[A-Z]{2,4}-') { ($device.DisplayName -split '-')[0] } else { "Unknown" }
            ServerLikelihood = if ($device.DisplayName -match "(server|srv|dc|sql|file|print)" -or $device.OperatingSystem -match "Server") { "High" } else { "Low" }
            RemoteAccessReady = if ($device.IsManaged -and $device.IsCompliant -and ($device.LastSignInDateTime -gt (Get-Date).AddDays(-7) -or $device.ApproximateLastSignInDateTime -gt (Get-Date).AddDays(-7))) { "Yes" } else { "No" }
            QueryTimestamp = Get-Date
            ProcessingStatus = "Basic Info Only"
        }
        
        # Try to get enhanced info for managed devices (with timeout)
        if ($device.IsManaged) {
            Write-Host "  Getting enhanced info for managed device..." -ForegroundColor Yellow
            
            $enhancedInfo = Get-DeviceInfoWithTimeout -Device $device -TimeoutSeconds $TimeoutSeconds
            
            if ($enhancedInfo.Success -and $enhancedInfo.ManagedDevice) {
                $deviceInfo.PrimaryUser = $enhancedInfo.PrimaryUser
                $deviceInfo.SerialNumber = $enhancedInfo.ManagedDevice.SerialNumber
                $deviceInfo.Model = $enhancedInfo.ManagedDevice.Model
                $deviceInfo.Manufacturer = $enhancedInfo.ManagedDevice.Manufacturer
                $deviceInfo.ComplianceState = $enhancedInfo.ManagedDevice.ComplianceState
                $deviceInfo.JoinType = $enhancedInfo.ManagedDevice.JoinType
                $deviceInfo.ManagementAgent = $enhancedInfo.ManagedDevice.ManagementAgent
                $deviceInfo.LastSyncDateTime = $enhancedInfo.ManagedDevice.LastSyncDateTime
                $deviceInfo.ProcessingStatus = "Complete"
                Write-Host "  ✅ Enhanced info retrieved successfully" -ForegroundColor Green
            } else {
                Write-Warning "  ⚠️ Could not get enhanced info: $($enhancedInfo.Error)"
                $deviceInfo.PrimaryUser = "Timeout/Error"
                $deviceInfo.SerialNumber = "Timeout/Error"
                $deviceInfo.Model = "Timeout/Error"
                $deviceInfo.Manufacturer = "Timeout/Error"
                $deviceInfo.ComplianceState = "Timeout/Error"
                $deviceInfo.JoinType = "Timeout/Error"
                $deviceInfo.ManagementAgent = "Timeout/Error"
                $deviceInfo.LastSyncDateTime = "Timeout/Error"
                $deviceInfo.ProcessingStatus = "Timeout/Error: $($enhancedInfo.Error)"
                $skippedDevices += $device.DisplayName
            }
        } else {
            # Non-managed devices get minimal info
            $deviceInfo.PrimaryUser = "Not Managed"
            $deviceInfo.SerialNumber = "Not Available"
            $deviceInfo.Model = "Not Available"
            $deviceInfo.Manufacturer = "Not Available"
            $deviceInfo.ComplianceState = "Not Managed"
            $deviceInfo.JoinType = "Not Available"
            $deviceInfo.ManagementAgent = "Not Available"
            $deviceInfo.LastSyncDateTime = "Not Available"
            $deviceInfo.ProcessingStatus = "Not Managed"
        }
        
        $result += $deviceInfo
        
        Write-Host "  ✅ Device $count complete" -ForegroundColor Green
    }
    
    Write-Progress -Activity "Processing devices..." -Completed
    
    # Summary
    Write-Host "`n=== PROCESSING SUMMARY ===" -ForegroundColor Green
    Write-Host "Total devices processed: $total" -ForegroundColor White
    Write-Host "Successfully processed: $($total - $skippedDevices.Count)" -ForegroundColor Green
    Write-Host "Timed out/failed: $($skippedDevices.Count)" -ForegroundColor Red
    
    if ($skippedDevices.Count -gt 0) {
        Write-Host "`nDevices that timed out:" -ForegroundColor Yellow
        $skippedDevices | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    
    # Export results
    if ($ExportToCsv) {
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        $csvPath = Join-Path $OutputPath "DeviceInventory_NoHang_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $result | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "`nResults exported to: $csvPath" -ForegroundColor Green
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