# Network reconnaissance from inside
ipconfig /all
arp -a
route print
netstat -rn
nslookup buckhorn.org

# Look for VPN client software
Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*VPN*" -or $_.Name -like "*Cisco*" -or $_.Name -like "*SonicWall*" }

# Check for VPN network adapters
Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*VPN*" -or $_.InterfaceDescription -like "*TAP*" }