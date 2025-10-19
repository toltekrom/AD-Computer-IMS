#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

param(
    [string]$ConfigPath = "E:\Users\jerom\source\AD-Computer-IMS\config\appsettings.json",
    [string]$TargetDeviceName = "desktop-tn5mjd9"  # Replace with actual device name
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Deploy-RDPEnabler {
    param([string]$DeviceName)
    
    Write-Host "`n=== DEPLOYING RDP ENABLER TO $DeviceName ===" -ForegroundColor Cyan
    
    try {
        # Find the device in Intune
        $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$DeviceName'"
        
        if (-not $device) {
            Write-Host "❌ Device '$DeviceName' not found in Intune" -ForegroundColor Red
            return $false
        }
        
        Write-Host "✅ Found device: $($device.DeviceName)" -ForegroundColor Green
        Write-Host "   User: $($device.UserDisplayName)" -ForegroundColor Gray
        Write-Host "   Last Sync: $($device.LastSyncDateTime)" -ForegroundColor Gray
        
        # Create PowerShell script to enable RDP - simplified without nested here-strings
        $rdpScript = 'Write-Host "Enabling Remote Desktop..." -ForegroundColor Yellow' + "`n"
        $rdpScript += 'Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -name "fDenyTSConnections" -Value 0' + "`n"
        $rdpScript += 'Enable-NetFirewallRule -DisplayGroup "Remote Desktop"' + "`n"
        $rdpScript += 'Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -name "UserAuthentication" -Value 0' + "`n"
        $rdpScript += '$currentUser = $env:USERNAME' + "`n"
        $rdpScript += 'net localgroup "Remote Desktop Users" $currentUser /add 2>$null' + "`n"
        $rdpScript += '$networkInfo = @{' + "`n"
        $rdpScript += '    ComputerName = $env:COMPUTERNAME' + "`n"
        $rdpScript += '    UserName = $env:USERNAME' + "`n"
        $rdpScript += '    Domain = $env:USERDOMAIN' + "`n"
        $rdpScript += '    IPAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Select-Object -First 1).IPAddress' + "`n"
        $rdpScript += '    DateTime = Get-Date' + "`n"
        $rdpScript += '}' + "`n"
        $rdpScript += '$networkInfo | ConvertTo-Json | Out-File "$env:PUBLIC\Desktop\RDP_Connection_Info.txt" -Force' + "`n"
        $rdpScript += 'Write-Host "✅ RDP enabled successfully!" -ForegroundColor Green' + "`n"
        $rdpScript += 'Write-Host "Connection details saved to Desktop\RDP_Connection_Info.txt" -ForegroundColor Cyan' + "`n"
        
        # Create TeamViewer batch file content separately
        $teamViewerBatch = '@echo off' + "`n"
        $teamViewerBatch += 'echo Downloading TeamViewer QuickSupport...' + "`n"
        $teamViewerBatch += 'powershell -Command "Invoke-WebRequest -Uri ''https://download.teamviewer.com/download/TeamViewerQS.exe'' -OutFile ''%TEMP%\TeamViewerQS.exe''"' + "`n"
        $teamViewerBatch += 'echo Starting TeamViewer QuickSupport...' + "`n"
        $teamViewerBatch += 'start %TEMP%\TeamViewerQS.exe' + "`n"
        $teamViewerBatch += 'echo TeamViewer should now be running. Provide the ID and Password to your administrator.' + "`n"
        $teamViewerBatch += 'pause' + "`n"
        
        # Add TeamViewer batch creation to the RDP script
        $rdpScript += '$teamViewerContent = @"' + "`n"
        $rdpScript += $teamViewerBatch
        $rdpScript += '"@' + "`n"
        $rdpScript += '$teamViewerContent | Out-File "$env:PUBLIC\Desktop\Start_TeamViewer.bat" -Encoding ASCII -Force' + "`n"
        $rdpScript += 'Write-Host "✅ TeamViewer helper batch file created on Desktop" -ForegroundColor Green'
        
        Write-Host "`n📋 RDP DEPLOYMENT SCRIPT READY:" -ForegroundColor Yellow
        Write-Host $rdpScript -ForegroundColor Gray
        
        Write-Host "`n⚠️  DEPLOYMENT OPTIONS:" -ForegroundColor Yellow
        Write-Host "1. Manual deployment via Intune Admin Center" -ForegroundColor White
        Write-Host "2. PowerShell remoting (if already enabled)" -ForegroundColor White
        Write-Host "3. Ask user to run script manually" -ForegroundColor White
        Write-Host "4. Save script to file for manual execution" -ForegroundColor White
        
        # Save the script to a file for easy deployment
        $scriptPath = Join-Path $PSScriptRoot "RDP_Enabler_Script.ps1"
        $rdpScript | Out-File $scriptPath -Encoding UTF8 -Force
        Write-Host "`n💾 Script saved to: $scriptPath" -ForegroundColor Green
        
        return $true
        
    } catch {
        Write-Host "❌ Error deploying RDP enabler: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    if ($TargetDeviceName -ne "ACCOUNTING_PC_NAME") {
        $result = Deploy-RDPEnabler -DeviceName $TargetDeviceName
        if ($result) {
            Write-Host "`n✅ RDP enabler script generated successfully!" -ForegroundColor Green
            Write-Host "Next steps:" -ForegroundColor Yellow
            Write-Host "1. Deploy the generated script via Intune" -ForegroundColor White
            Write-Host "2. Or manually run the script on the target device" -ForegroundColor White
        }
    } else {
        Write-Host "`n❌ Please specify the actual accounting PC device name" -ForegroundColor Red
        Write-Host "Check your device inventory for the exact name" -ForegroundColor Yellow
    }
    
} catch {
    Write-Error "Failed to deploy RDP enabler: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}