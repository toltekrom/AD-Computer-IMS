#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

param(
    [string]$ConfigPath = "E:\Users\jerom\source\AD-Computer-IMS\config\appsettings.json",  # Fixed path
    [int]$DaysBack = 30
)

# Import your configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Test-RequiredPermissions {
    Write-Host "`n=== CHECKING CURRENT APP PERMISSIONS ===" -ForegroundColor Cyan
    
    try {
        $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$clientId'"
        $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id
        
        $hasAuditLogPermission = $false
        
        Write-Host "Current Microsoft Graph Permissions:" -ForegroundColor Yellow
        foreach ($assignment in $appRoleAssignments) {
            $resourceSP = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId
            if ($resourceSP.DisplayName -eq "Microsoft Graph") {
                $appRole = $resourceSP.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
                if ($appRole) {
                    Write-Host "✅ $($appRole.Value)" -ForegroundColor Green
                    if ($appRole.Value -eq "AuditLog.Read.All") {
                        $hasAuditLogPermission = $true
                    }
                }
            }
        }
        
        return $hasAuditLogPermission
    }
    catch {
        Write-Host "❌ Error checking permissions: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Search-SageAppClues {
    Write-Host "`n=== SEARCHING FOR SAGE APP CLUES ===" -ForegroundColor Cyan
    
    # Check current app registrations for anything Sage-related
    try {
        $apps = Get-MgApplication -All
        
        Write-Host "`nLooking for Sage-related apps..." -ForegroundColor Yellow
        $sageApps = $apps | Where-Object { 
            $_.DisplayName -like "*Sage*" -or 
            $_.DisplayName -like "*sage*" -or
            $_.Description -like "*Sage*"
        }
        
        if ($sageApps) {
            Write-Host "🎯 FOUND SAGE-RELATED APPS:" -ForegroundColor Green
            foreach ($app in $sageApps) {
                Write-Host "`n📱 $($app.DisplayName)" -ForegroundColor White
                Write-Host "   App ID: $($app.AppId)" -ForegroundColor Gray
                Write-Host "   Created: $($app.CreatedDateTime)" -ForegroundColor Gray
                Write-Host "   Description: $($app.Description)" -ForegroundColor Gray
                
                # Check current permissions
                if ($app.RequiredResourceAccess) {
                    Write-Host "   Current API Permissions:" -ForegroundColor Yellow
                    foreach ($resource in $app.RequiredResourceAccess) {
                        try {
                            $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($resource.ResourceAppId)'" -ErrorAction SilentlyContinue
                            $resourceName = $servicePrincipal.DisplayName ?? $resource.ResourceAppId
                            Write-Host "     🔗 $resourceName" -ForegroundColor Cyan
                            
                            foreach ($permission in $resource.ResourceAccess) {
                                if ($servicePrincipal) {
                                    $permissionName = ($servicePrincipal.AppRoles | Where-Object { $_.Id -eq $permission.Id }).Value
                                    if (-not $permissionName) {
                                        $permissionName = ($servicePrincipal.Oauth2PermissionScopes | Where-Object { $_.Id -eq $permission.Id }).Value
                                    }
                                    Write-Host "       - $($permissionName ?? $permission.Id)" -ForegroundColor Gray
                                }
                            }
                        }
                        catch {
                            Write-Host "     🔗 $($resource.ResourceAppId) (Unknown resource)" -ForegroundColor Cyan
                        }
                    }
                } else {
                    Write-Host "   ❌ No API permissions currently configured" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "❌ No current Sage apps found" -ForegroundColor Red
            Write-Host "   The Sage app may have been deleted entirely" -ForegroundColor Gray
        }
        
        return $sageApps
    }
    catch {
        Write-Host "❌ Error searching for Sage apps: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-CommonSagePermissions {
    Write-Host "`n=== COMMON SAGE APP PERMISSIONS ===" -ForegroundColor Cyan
    Write-Host "Based on typical Sage integrations, it likely had these permissions:" -ForegroundColor Yellow
    
    $commonSagePermissions = @(
        @{ Name = "User.Read.All"; Description = "Read all users' full profiles" },
        @{ Name = "Directory.Read.All"; Description = "Read directory data" },
        @{ Name = "Files.ReadWrite.All"; Description = "Read and write files (for document management)" },
        @{ Name = "Sites.ReadWrite.All"; Description = "Read and write items in all site collections" },
        @{ Name = "Calendars.ReadWrite"; Description = "Read and write calendars" },
        @{ Name = "Contacts.ReadWrite"; Description = "Read and write contacts" },
        @{ Name = "Mail.Send"; Description = "Send mail as users" },
        @{ Name = "Group.ReadWrite.All"; Description = "Read and write all groups" }
    )
    
    foreach ($perm in $commonSagePermissions) {
        Write-Host "🔧 $($perm.Name)" -ForegroundColor Yellow
        Write-Host "   Purpose: $($perm.Description)" -ForegroundColor Gray
    }
    
    Write-Host "`n💡 SAGE INTEGRATION INSIGHTS:" -ForegroundColor Cyan
    Write-Host "- Sage typically integrates with Office 365 for:" -ForegroundColor Gray
    Write-Host "  • User authentication and directory sync" -ForegroundColor Gray
    Write-Host "  • Document management (SharePoint)" -ForegroundColor Gray
    Write-Host "  • Email integration (Outlook)" -ForegroundColor Gray
    Write-Host "  • Calendar and scheduling integration" -ForegroundColor Gray
    Write-Host "- If this was removed, users might have lost:" -ForegroundColor Gray
    Write-Host "  • Single sign-on to Sage" -ForegroundColor Gray
    Write-Host "  • Automatic document sync" -ForegroundColor Gray
    Write-Host "  • Email integration from Sage" -ForegroundColor Gray
}

function Search-AuditLogsForSage {
    param([bool]$HasPermission)
    
    if (-not $HasPermission) {
        Write-Host "`n=== AUDIT LOG ACCESS REQUIRED ===" -ForegroundColor Red
        Write-Host "❌ Cannot access audit logs without AuditLog.Read.All permission" -ForegroundColor Red
        Write-Host "`n📋 TO ADD THE PERMISSION:" -ForegroundColor Yellow
        Write-Host "1. Go to Azure Portal → App registrations → Your app" -ForegroundColor White
        Write-Host "2. API permissions → Add permission → Microsoft Graph" -ForegroundColor White
        Write-Host "3. Application permissions → Search 'AuditLog.Read.All'" -ForegroundColor White
        Write-Host "4. Add permission → Grant admin consent" -ForegroundColor White
        Write-Host "5. Re-run this script" -ForegroundColor White
        return
    }
    
    Write-Host "`n=== SEARCHING AUDIT LOGS FOR SAGE ACTIVITY ===" -ForegroundColor Cyan
    
    try {
        # Get the maximum available date range for audit logs
        # Azure AD audit logs are typically retained for 30 days for free tier
        $maxDaysBack = [Math]::Min($DaysBack, 30)
        $startDate = (Get-Date).AddDays(-$maxDaysBack)
        
        Write-Host "Searching audit logs from $($startDate.ToString('yyyy-MM-dd')) to present..." -ForegroundColor Yellow
        Write-Host "Note: Azure AD audit logs are retained for 30 days maximum" -ForegroundColor Gray
        
        # Format the date properly for Microsoft Graph API
        $filterDate = $startDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        
        Write-Host "Using filter date: $filterDate" -ForegroundColor Gray
        
        # Search for Sage-related audit entries with corrected date format
        $auditLogs = Get-MgAuditLogDirectoryAudit -Filter "activityDateTime ge $filterDate" -Top 1000 | 
            Where-Object { 
                $_.ActivityDisplayName -like "*Sage*" -or
                $_.ActivityDisplayName -like "*sage*" -or
                ($_.AdditionalDetails -and ($_.AdditionalDetails | Where-Object { $_.Value -like "*Sage*" -or $_.Value -like "*sage*" })) -or
                ($_.TargetResources -and ($_.TargetResources | Where-Object { $_.DisplayName -like "*Sage*" -or $_.DisplayName -like "*sage*" }))
            }
        
        if ($auditLogs -and $auditLogs.Count -gt 0) {
            Write-Host "🎯 FOUND SAGE-RELATED AUDIT ENTRIES ($($auditLogs.Count) total):" -ForegroundColor Green
            
            foreach ($log in $auditLogs | Sort-Object ActivityDateTime -Descending | Select-Object -First 20) {
                Write-Host "`n📅 $($log.ActivityDateTime)" -ForegroundColor White
                Write-Host "   Activity: $($log.ActivityDisplayName)" -ForegroundColor Gray
                Write-Host "   Result: $($log.Result)" -ForegroundColor Gray
                Write-Host "   User: $($log.InitiatedBy.User.UserPrincipalName ?? $log.InitiatedBy.App.DisplayName ?? 'System')" -ForegroundColor Gray
                
                if ($log.TargetResources) {
                    foreach ($target in $log.TargetResources) {
                        if ($target.DisplayName) {
                            Write-Host "   Target: $($target.DisplayName)" -ForegroundColor Cyan
                        }
                        if ($target.ModifiedProperties) {
                            Write-Host "   Modified Properties:" -ForegroundColor Yellow
                            foreach ($prop in $target.ModifiedProperties) {
                                Write-Host "     - $($prop.DisplayName): $($prop.OldValue) → $($prop.NewValue)" -ForegroundColor Gray
                            }
                        }
                    }
                }
                
                if ($log.AdditionalDetails) {
                    $relevantDetails = $log.AdditionalDetails | Where-Object { 
                        $_.Value -like "*Sage*" -or $_.Value -like "*sage*" -or
                        $_.Key -like "*permission*" -or $_.Key -like "*scope*"
                    }
                    if ($relevantDetails) {
                        Write-Host "   Additional Details:" -ForegroundColor Yellow
                        foreach ($detail in $relevantDetails) {
                            Write-Host "     $($detail.Key): $($detail.Value)" -ForegroundColor Gray
                        }
                    }
                }
            }
        } else {
            Write-Host "❌ No Sage-related audit entries found in last $maxDaysBack days" -ForegroundColor Red
            Write-Host "   This could mean:" -ForegroundColor Gray
            Write-Host "   • The Sage app changes happened more than 30 days ago" -ForegroundColor Gray
            Write-Host "   • The app was named something other than 'Sage'" -ForegroundColor Gray
            Write-Host "   • The changes were made outside of Azure AD" -ForegroundColor Gray
            
            # Let's also search for general application permission changes
            Write-Host "`n   Searching for general permission changes instead..." -ForegroundColor Yellow
            
            $permissionLogs = Get-MgAuditLogDirectoryAudit -Filter "activityDateTime ge $filterDate" -Top 500 | 
                Where-Object { 
                    $_.ActivityDisplayName -like "*permission*" -or
                    $_.ActivityDisplayName -like "*consent*" -or
                    $_.ActivityDisplayName -like "*Update application*" -or
                    $_.Category -eq "ApplicationManagement"
                }
            
            if ($permissionLogs -and $permissionLogs.Count -gt 0) {
                Write-Host "   📋 Found $($permissionLogs.Count) general permission-related changes:" -ForegroundColor Cyan
                
                foreach ($log in $permissionLogs | Sort-Object ActivityDateTime -Descending | Select-Object -First 10) {
                    Write-Host "`n   📅 $($log.ActivityDateTime)" -ForegroundColor White
                    Write-Host "      Activity: $($log.ActivityDisplayName)" -ForegroundColor Gray
                    Write-Host "      User: $($log.InitiatedBy.User.UserPrincipalName ?? 'System')" -ForegroundColor Gray
                    
                    if ($log.TargetResources -and $log.TargetResources[0].DisplayName) {
                        Write-Host "      App: $($log.TargetResources[0].DisplayName)" -ForegroundColor Cyan
                    }
                }
            }
        }
    }
    catch {
        Write-Host "❌ Error accessing audit logs: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Full error details: $($_.Exception)" -ForegroundColor Gray
        
        # If it's still a date range error, try with just the last 7 days
        if ($_.Exception.Message -like "*Minimum allowed time*") {
            Write-Host "`n   Retrying with last 7 days only..." -ForegroundColor Yellow
            try {
                $recentStartDate = (Get-Date).AddDays(-7)
                $recentFilterDate = $recentStartDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                
                $recentLogs = Get-MgAuditLogDirectoryAudit -Filter "activityDateTime ge $recentFilterDate" -Top 100 | 
                    Where-Object { $_.Category -eq "ApplicationManagement" }
                
                if ($recentLogs) {
                    Write-Host "   ✅ Found $($recentLogs.Count) recent application management activities" -ForegroundColor Green
                } else {
                    Write-Host "   ❌ No recent application management activities found" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "   ❌ Still unable to access audit logs: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Debug: Show what config path we're using
    Write-Host "Using config file: $ConfigPath" -ForegroundColor Gray
    Write-Host "Config file exists: $(Test-Path $ConfigPath)" -ForegroundColor Gray
    
    # Check current permissions
    $hasAuditPermission = Test-RequiredPermissions
    
    # Search for current Sage apps
    $sageApps = Search-SageAppClues
    
    # Show common Sage permissions
    Get-CommonSagePermissions
    
    # Try to search audit logs if we have permission
    Search-AuditLogsForSage -HasPermission $hasAuditPermission
    
    Write-Host "`n=== RECOMMENDATIONS ===" -ForegroundColor Cyan
    if (-not $sageApps) {
        Write-Host "🔧 The Sage app appears to have been completely removed" -ForegroundColor Yellow
        Write-Host "🔧 You may need to recreate it with proper permissions" -ForegroundColor Yellow
        Write-Host "🔧 Contact Sage support for their recommended Azure AD integration setup" -ForegroundColor Yellow
        Write-Host "🔧 Check with users if they're having Sage login/integration issues" -ForegroundColor Yellow
    } else {
        Write-Host "🔧 Sage app still exists but may need permissions restored" -ForegroundColor Yellow
        Write-Host "🔧 Check with users if Sage integration is still working" -ForegroundColor Yellow
    }
    
    if (-not $hasAuditPermission) {
        Write-Host "🔧 Add AuditLog.Read.All permission to investigate permission history" -ForegroundColor Yellow
    }
    
    Write-Host "`n💡 AUDIT LOG LIMITATIONS:" -ForegroundColor Cyan
    Write-Host "- Azure AD audit logs are only retained for 30 days (free tier)" -ForegroundColor Gray
    Write-Host "- If Sage permission changes were made >30 days ago, they won't appear" -ForegroundColor Gray
    Write-Host "- Consider checking with users about recent Sage functionality issues" -ForegroundColor Gray
    
} catch {
    Write-Error "Failed to check Sage app history: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue  # Fixed typo: was Disconnect-MsgGraph
}