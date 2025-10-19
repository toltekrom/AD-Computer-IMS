#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\appsettings.json")
)

# Import your configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

try {
    # Connect using your existing app
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Get your app registration details
    $app = Get-MgApplication -Filter "appId eq '$clientId'"
    
    Write-Host "`n=== YOUR APP REGISTRATION ANALY    .\Check-AppPermissions.ps1SIS ===" -ForegroundColor Cyan
    Write-Host "App Name: $($app.DisplayName)" -ForegroundColor White
    Write-Host "App ID: $clientId" -ForegroundColor White
    Write-Host "Tenant: $tenantId" -ForegroundColor White
    
    # Get current API permissions
    $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$clientId'"
    
    if ($servicePrincipal) {
        Write-Host "`n=== CURRENT MICROSOFT GRAPH PERMISSIONS ===" -ForegroundColor Cyan
        
        # Get app role assignments (Application permissions)
        $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id
        
        foreach ($assignment in $appRoleAssignments) {
            $resourceSP = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId
            if ($resourceSP.DisplayName -eq "Microsoft Graph") {
                $appRole = $resourceSP.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
                if ($appRole) {
                    Write-Host "✅ $($appRole.Value) - $($appRole.DisplayName)" -ForegroundColor Green
                }
            }
        }
    }
    
    Write-Host "`n=== RECOMMENDED PERMISSIONS FOR REMOTE DEVICE MANAGEMENT ===" -ForegroundColor Cyan
    
    $recommendedPermissions = @(
        @{ Name = "DeviceManagementManagedDevices.ReadWrite.All"; Description = "Full device management access" },
        @{ Name = "DeviceManagementManagedDevices.PrivilegedOperations.All"; Description = "Remote device actions (restart, run scripts)" },
        @{ Name = "DeviceManagementApps.ReadWrite.All"; Description = "Deploy and manage applications" },
        @{ Name = "DeviceManagementConfiguration.ReadWrite.All"; Description = "Manage device configurations" },
        @{ Name = "User.ReadWrite.All"; Description = "Read/write all user info" },
        @{ Name = "Directory.ReadWrite.All"; Description = "Broad directory access" }
    )
    
    foreach ($perm in $recommendedPermissions) {
        Write-Host "🔧 $($perm.Name)" -ForegroundColor Yellow
        Write-Host "   Purpose: $($perm.Description)" -ForegroundColor Gray
    }
    
    Write-Host "`n=== NEXT STEPS FOR REMOTE ACCESS ===" -ForegroundColor Cyan
    Write-Host "1. Add the recommended permissions above to your current app registration" -ForegroundColor Yellow
    Write-Host "2. Grant admin consent for the new permissions" -ForegroundColor Yellow
    Write-Host "3. Use Intune to deploy remote access software to managed devices" -ForegroundColor Yellow
    Write-Host "4. Target the 'RemoteAccessReady = Yes' devices from your inventory" -ForegroundColor Yellow
    
    Write-Host "`n=== P2P SERVER APP ASSESSMENT ===" -ForegroundColor Cyan
    Write-Host "❌ P2P Server app is configured as an API resource, not a client" -ForegroundColor Red
    Write-Host "❌ No Microsoft Graph permissions - can't help with device management" -ForegroundColor Red
    Write-Host "ℹ️  The 'urn:p2p_cert/user_impersonation' scope suggests it's for a custom service" -ForegroundColor Gray
    Write-Host "ℹ️  This might be related to legacy remote access software from previous IT admin" -ForegroundColor Gray
    
} catch {
    Write-Error "Failed to analyze app permissions: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}