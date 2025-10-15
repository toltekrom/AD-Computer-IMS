# Look for VPN configurations on current system
Write-Host "`n=== VPN CONFIGURATION DISCOVERY ===" -ForegroundColor Magenta

# Check for VPN connections
Write-Host "Existing VPN connections:"
Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  VPN: $($_.Name) -> $($_.ServerAddress)" -ForegroundColor Cyan
}

# Look for VPN client software
Write-Host "`nVPN Client Software:"
$vpnSoftware = Get-WmiObject -Class Win32_Product | Where-Object {
    $_.Name -like "*VPN*" -or $_.Name -like "*Cisco*" -or $_.Name -like "*Fortinet*" -or 
    $_.Name -like "*SonicWall*" -or $_.Name -like "*Pulse*" -or $_.Name -like "*GlobalProtect*"
}
$vpnSoftware | ForEach-Object {
    Write-Host "  Found: $($_.Name)" -ForegroundColor Green
}

# Check network adapters for VPN interfaces
Write-Host "`nVPN Network Adapters:"
Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -like "*VPN*" -or $_.InterfaceDescription -like "*TAP*" -or
    $_.InterfaceDescription -like "*Cisco*" -or $_.Name -like "*VPN*"
} | ForEach-Object {
    Write-Host "  VPN Adapter: $($_.Name) - $($_.InterfaceDescription)" -ForegroundColor Cyan
}