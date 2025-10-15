Write-Host "Enabling Remote Desktop..." -ForegroundColor Yellow
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -name "UserAuthentication" -Value 0
$currentUser = $env:USERNAME
net localgroup "Remote Desktop Users" $currentUser /add 2>$null
$networkInfo = @{
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    Domain = $env:USERDOMAIN
    IPAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Select-Object -First 1).IPAddress
    DateTime = Get-Date
}
$networkInfo | ConvertTo-Json | Out-File "$env:PUBLIC\Desktop\RDP_Connection_Info.txt" -Force
Write-Host "✅ RDP enabled successfully!" -ForegroundColor Green
Write-Host "Connection details saved to Desktop\RDP_Connection_Info.txt" -ForegroundColor Cyan
$teamViewerContent = @"
@echo off
echo Downloading TeamViewer QuickSupport...
powershell -Command "Invoke-WebRequest -Uri 'https://download.teamviewer.com/download/TeamViewerQS.exe' -OutFile '%TEMP%\TeamViewerQS.exe'"
echo Starting TeamViewer QuickSupport...
start %TEMP%\TeamViewerQS.exe
echo TeamViewer should now be running. Provide the ID and Password to your administrator.
pause
"@
$teamViewerContent | Out-File "$env:PUBLIC\Desktop\Start_TeamViewer.bat" -Encoding ASCII -Force
Write-Host "✅ TeamViewer helper batch file created on Desktop" -ForegroundColor Green
