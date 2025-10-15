# Connect with your current admin account
Connect-MgGraph -Scopes "User.ReadWrite.All"

# Reset password for the admin account
$newPassword = ConvertTo-SecureString "NewPassword123!" -AsPlainText -Force
Set-MgUser -UserId "admin.pcwa@pcwabuckhorn.onmicrosoft.com" -PasswordProfile @{
    Password = $newPassword
    ForceChangePasswordNextSignIn = $false
}
# Option 3: Create Your Own Device Admin Account
# You could create a new user with the same role:

# Create new admin user
$newAdmin = New-MgUser -DisplayName "Your Admin Account" -UserPrincipalName "youradmin@buckhorn.org" -PasswordProfile @{
    Password = "TempPassword123!"
    ForceChangePasswordNextSignIn = $true
} -AccountEnabled:$true

# Assign the Device Administrator role
$roleDefinition = Get-MgDirectoryRoleTemplate | Where-Object { $_.DisplayName -eq "Azure AD Joined Device Local Administrator" }
$directoryRole = Get-MgDirectoryRole | Where-Object { $_.RoleTemplateId -eq $roleDefinition.Id }
New-MgDirectoryRoleMemberByRef -DirectoryRoleId $directoryRole.Id -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($newAdmin.Id)" }

# Test if you can reach the AD server
Test-NetConnection -ComputerName "192.168.102.230" -Port 3389  # RDP
Test-NetConnection -ComputerName "192.168.102.230" -Port 445   # SMB/File sharing
Test-NetConnection -ComputerName "192.168.102.230" -Port 389   # LDAP

# Try to resolve the hostname
Resolve-DnsName "PCWAD1.internal.buckhorn.org"

# Try RDP directly
mstsc /v:192.168.102.230

# Try accessing file shares
\\192.168.102.230\c$
\\192.168.102.230\admin$

# Test if PowerShell remoting is available
Test-WSMan -ComputerName "192.168.102.230"

# Try to create a session (will need credentials)
$session = New-PSSession -ComputerName "192.168.102.230"

# Quick tests to run immediately
Test-NetConnection -ComputerName "BUCKHORN_ADMIN" -Port 3389
Test-NetConnection -ComputerName "192.168.102.230" -Port 3389
whoami /groups  # Check your current privileges
net use  # Check existing network connections