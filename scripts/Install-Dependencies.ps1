# Install required PowerShell modules
Write-Host "Installing Microsoft Graph PowerShell modules..." -ForegroundColor Yellow

$modules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.DeviceManagement", 
    "Microsoft.Graph.Identity.DirectoryManagement",
    "Microsoft.Graph.Users"
)

foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing $module..." -ForegroundColor Green
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    } else {
        Write-Host "$module is already installed" -ForegroundColor Cyan
    }
}

Write-Host "All dependencies installed successfully!" -ForegroundColor Green