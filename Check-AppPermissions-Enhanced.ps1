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
    
    Write-Host "`n=== COMPREHENSIVE APP REGISTRATION AUDIT ===" -ForegroundColor Cyan
    
    # Get all app registrations to find the Connect sync and P2P apps
    $allApps = Get-MgApplication -All
    
    # Find specific apps of interest
    $connectSyncApp = $allApps | Where-Object { $_.DisplayName -like "*ConnectSyncProvisioning*" }
    $p2pApp = $allApps | Where-Object { $_.DisplayName -like "*P2P*" }
    $yourApp = $allApps | Where-Object { $_.AppId -eq $clientId }
    
    Write-Host "`n=== YOUR DEVICE INVENTORY APP ===" -ForegroundColor Green
    if ($yourApp) {
        Write-Host "App Name: $($yourApp.DisplayName)" -ForegroundColor White
        Write-Host "App ID: $clientId" -ForegroundColor White
        
        # Get current permissions
        $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$clientId'"
        if ($servicePrincipal) {
            $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id
            
            Write-Host "`nCurrent Microsoft Graph Permissions:" -ForegroundColor Yellow
            foreach ($assignment in $appRoleAssignments) {
                $resourceSP = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId
                if ($resourceSP.DisplayName -eq "Microsoft Graph") {
                    $appRole = $resourceSP.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
                    if ($appRole) {
                        Write-Host "✅ $($appRole.Value)" -ForegroundColor Green
                    }
                }
            }
        }
    }
    
    Write-Host "`n=== AZURE AD CONNECT SYNC APP ===" -ForegroundColor Cyan
    if ($connectSyncApp) {
        Write-Host "🔍 Found: $($connectSyncApp.DisplayName)" -ForegroundColor White
        Write-Host "App ID: $($connectSyncApp.AppId)" -ForegroundColor White
        Write-Host "Created: $($connectSyncApp.CreatedDateTime)" -ForegroundColor White
        
        # This suggests on-premise infrastructure
        Write-Host "`n💡 INSIGHTS:" -ForegroundColor Yellow
        Write-Host "- This confirms Azure AD Connect is/was configured" -ForegroundColor Gray
        Write-Host "- PCWAD1 likely = Presbyterian Child Welfare Agency Domain Controller 1" -ForegroundColor Gray
        Write-Host "- There should be an on-premise Active Directory server" -ForegroundColor Gray
        Write-Host "- Your two mystery IP addresses might be:" -ForegroundColor Gray
        Write-Host "  • Domain Controller (PCWAD1)" -ForegroundColor Gray
        Write-Host "  • Another server (possibly the billing server)" -ForegroundColor Gray
        
        # Check if it has any useful permissions
        $connectSP = Get-MgServicePrincipal -Filter "appId eq '$($connectSyncApp.AppId)'" -ErrorAction SilentlyContinue
        if ($connectSP) {
            $connectAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $connectSP.Id -ErrorAction SilentlyContinue
            if ($connectAssignments) {
                Write-Host "`nAzure AD Connect Permissions:" -ForegroundColor Yellow
                foreach ($assignment in $connectAssignments) {
                    $resourceSP = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId -ErrorAction SilentlyContinue
                    if ($resourceSP -and $resourceSP.DisplayName -eq "Microsoft Graph") {
                        $appRole = $resourceSP.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
                        if ($appRole) {
                            Write-Host "  - $($appRole.Value)" -ForegroundColor Gray
                        }
                    }
                }
            }
        }
    } else {
        Write-Host "❌ No Azure AD Connect sync app found" -ForegroundColor Red
    }
    
    Write-Host "`n=== P2P SERVER APP ===" -ForegroundColor Cyan
    if ($p2pApp) {
        Write-Host "🔍 Found: $($p2pApp.DisplayName)" -ForegroundColor White
        Write-Host "App ID: $($p2pApp.AppId)" -ForegroundColor White
        Write-Host "Created: $($p2pApp.CreatedDateTime)" -ForegroundColor White
        
        Write-Host "`n💡 THEORY:" -ForegroundColor Yellow
        Write-Host "- P2P Server might be related to Azure AD Connect writeback" -ForegroundColor Gray
        Write-Host "- Or it could be a first attempt at hybrid identity setup" -ForegroundColor Gray
        Write-Host "- The custom scope 'urn:p2p_cert/user_impersonation' suggests" -ForegroundColor Gray
        Write-Host "  it was meant to provide authentication for some service" -ForegroundColor Gray
    } else {
        Write-Host "❌ No P2P Server app found" -ForegroundColor Red
    }
    
    Write-Host "`n=== NETWORK DISCOVERY STRATEGY ===" -ForegroundColor Cyan
    Write-Host "Based on the Azure AD Connect evidence:" -ForegroundColor Yellow
    Write-Host "1. Your two mystery IP addresses likely include PCWAD1 (Domain Controller)" -ForegroundColor White
    Write-Host "2. Look for devices in your inventory with 'DC', 'PCWA', or 'Server' in the name" -ForegroundColor White
    Write-Host "3. Check if Azure AD Connect is still running (affects hybrid identity)" -ForegroundColor White
    Write-Host "4. The on-premise AD might have more detailed computer/user info" -ForegroundColor White
    
    Write-Host "`n=== RECOMMENDED PERMISSIONS TO ADD ===" -ForegroundColor Cyan
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
    
    Write-Host "`n=== NEXT DETECTIVE STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Run your device inventory with -DetectiveMode to find server-like devices" -ForegroundColor Yellow
    Write-Host "2. Look for devices with names like 'PCWA-DC01', 'PCWA-SVR01', etc." -ForegroundColor Yellow
    Write-Host "3. Check if those mystery IP addresses ping/respond" -ForegroundColor Yellow
    Write-Host "4. Try to identify which device corresponds to PCWAD1" -ForegroundColor Yellow
    Write-Host "5. Add remote management permissions to your app registration" -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to analyze app permissions: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}