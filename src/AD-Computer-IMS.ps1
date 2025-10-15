#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement

param(
    [string]$ConfigPath = ".\config\appsettings.json",
    [string]$OutputPath = ".\output",
    [switch]$ExportToCsv,
    [switch]$ReturnJson
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json

# Authentication using your app registration
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

try {
    # Connect to Microsoft Graph using certificate authentication
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Get all devices from Azure AD
    Write-Host "Querying devices from Microsoft Graph..." -ForegroundColor Yellow
    
    $devices = Get-MgDevice -All -Property "Id,DisplayName,OperatingSystem,OperatingSystemVersion,LastSignInDateTime,ApproximateLastSignInDateTime,DeviceId,IsCompliant,IsManaged,TrustType,ProfileType,SystemLabels,DeviceOwnership"
    
    $result = @()
    $total = $devices.Count
    $count = 0
    
    Write-Host "Processing $total devices..." -ForegroundColor Yellow
    
    foreach ($device in $devices) {
        $count++
        Write-Progress -Activity "Processing devices..." -Status "Processing $($device.DisplayName) ($count of $total)" -PercentComplete (($count / $total) * 100)
        
        # Get additional device details if managed by Intune
        $managedDevice = $null
        if ($device.IsManaged) {
            try {
                $managedDevice = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$($device.DeviceId)'" -ErrorAction SilentlyContinue
            } catch {
                Write-Verbose "Could not retrieve managed device info for $($device.DisplayName)"
            }
        }
        
        # Get primary user if available
        $primaryUser = $null
        if ($managedDevice -and $managedDevice.UserId) {
            try {
                $user = Get-MgUser -UserId $managedDevice.UserId -ErrorAction SilentlyContinue
                $primaryUser = $user.UserPrincipalName
            } catch {
                Write-Verbose "Could not retrieve user info for device $($device.DisplayName)"
            }
        }
        
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
            SerialNumber = $managedDevice.SerialNumber
            Model = $managedDevice.Model
            Manufacturer = $managedDevice.Manufacturer
            ComplianceState = $managedDevice.ComplianceState
            JoinType = $managedDevice.JoinType
            ManagementAgent = $managedDevice.ManagementAgent
            LastSyncDateTime = $managedDevice.LastSyncDateTime
            QueryTimestamp = Get-Date
        }
    }
    
    # Output results based on parameters
    if ($ExportToCsv) {
        $csvPath = Join-Path $OutputPath "DeviceInventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $result | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "Results exported to: $csvPath" -ForegroundColor Green
    }
    
    if ($ReturnJson) {
        return ($result | ConvertTo-Json -Depth 3)
    }
    
    return $result
    
} catch {
    Write-Error "Failed to connect to Microsoft Graph or retrieve data: $($_.Exception.Message)"
    throw
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}