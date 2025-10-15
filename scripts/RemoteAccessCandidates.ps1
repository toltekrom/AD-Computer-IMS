# Add these Graph permissions to your App Registration:
# DeviceManagementApps.ReadWrite.All
# DeviceManagementConfiguration.ReadWrite.All
# DeviceManagementManagedDevices.PrivilegedOperations.All

# Enhanced device inventory with remote access preparation
function Get-RemoteAccessCandidates {
    param($devices)
    
    $candidates = $devices | Where-Object {
        $_.IsManaged -eq $true -and 
        $_.IsCompliant -eq $true -and
        $_.OperatingSystem -like "*Windows*" -and
        $_.LastSignIn -gt (Get-Date).AddDays(-7)
    }
    
    return $candidates | Select-Object DeviceName, PrimaryUser, LastSignIn, Model, DeviceOwnership
}