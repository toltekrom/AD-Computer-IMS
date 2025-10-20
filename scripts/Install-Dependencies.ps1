# Install required PowerShell modules
Write-Host "Installing Microsoft Graph PowerShell modules..." -ForegroundColor Yellow

# Ensure TLS 1.2 for PSGallery connectivity
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ensure NuGet provider is available
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet provider..." -ForegroundColor Green
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop
}

$modules = @(
    "Microsoft.Graph",
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.DeviceManagement",
    "Microsoft.Graph.Identity.DirectoryManagement",
    "Microsoft.Graph.Users"
)

foreach ($module in $modules) {
    try {
        if (!(Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing $module..." -ForegroundColor Green
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        } else {
            Write-Host "$module is already installed" -ForegroundColor Cyan
        }
    } catch {
        Write-Warning ("Failed to install {0}: {1}" -f $module, $_.Exception.Message)
    }
}

Write-Host "Dependency installation complete (some installs may have warnings)." -ForegroundColor Green