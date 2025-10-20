<#
.SYNOPSIS
Creates a self-signed certificate in the CurrentUser cert store, exports the public .cer and (optionally) a .pfx, and prints the thumbprint.

.DESCRIPTION
This helper creates a self-signed certificate suitable for uploading to an Azure App Registration (Certificates & secrets -> Upload certificate).
By default it creates the cert in Cert:\CurrentUser\My and exports the public certificate to $env:TEMP.

.EXAMPLE
.\Create-SelfSignedCert.ps1 -Subject "CN=MyApp-ADComputer-IMS" -ValidMonths 24 -ExportPfx -PfxPath C:\temp\mycert.pfx

#>

param(
    [Parameter()]
    [string]$Subject = "CN=AD-Computer-IMS",

    [Parameter()]
    [string]$StoreLocation = "Cert:\CurrentUser\My",

    [Parameter()]
    [int]$KeyLength = 2048,

    [Parameter()]
    [int]$ValidMonths = 12,

    [Parameter()]
    [switch]$ExportPfx,

    [Parameter()]
    [string]$PublicCertPath = ([IO.Path]::Combine($env:TEMP, 'AD-Computer-IMS.cer')),

    [Parameter()]
    [string]$PfxPath = ([IO.Path]::Combine($env:TEMP, 'AD-Computer-IMS.pfx')),

    [Parameter()]
    [switch]$Overwrite
)

function Write-Ok($msg){ Write-Host $msg -ForegroundColor Green }
function Write-Info($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-WarnMsg($msg){ Write-Host $msg -ForegroundColor Yellow }

if ((Test-Path $PublicCertPath) -and (-not $Overwrite)){
    throw "Public cert path '$PublicCertPath' already exists. Use -Overwrite to replace."
}

if (($ExportPfx) -and (Test-Path $PfxPath) -and (-not $Overwrite)){
    throw "PFX path '$PfxPath' already exists. Use -Overwrite to replace."
}

Write-Info "Creating self-signed certificate with subject: $Subject"

try {
    $notAfter = (Get-Date).AddMonths($ValidMonths)
    $cert = New-SelfSignedCertificate -Subject $Subject `
        -CertStoreLocation $StoreLocation `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -KeyLength $KeyLength `
        -KeyAlgorithm RSA `
        -HashAlgorithm SHA256 `
        -NotAfter $notAfter

    if (-not $cert) { throw "New-SelfSignedCertificate returned nothing." }

    $thumbprint = $cert.Thumbprint
    Write-Ok "Certificate created in store: $StoreLocation"
    Write-Ok "Thumbprint: $thumbprint"

    # Export public cert (.cer)
    $publicDir = [IO.Path]::GetDirectoryName($PublicCertPath)
    if (-not (Test-Path $publicDir)) { New-Item -ItemType Directory -Path $publicDir -Force | Out-Null }
    Export-Certificate -Cert $cert -FilePath $PublicCertPath -Force
    Write-Ok "Public certificate exported to: $PublicCertPath"

    if ($ExportPfx) {
        # Prompt for password to protect the PFX
        $securePwd = Read-Host -AsSecureString "Enter a password to protect the exported PFX file"
        if (-not $securePwd) { throw "PFX export requires a password." }

        $pfxDir = [IO.Path]::GetDirectoryName($PfxPath)
        if (-not (Test-Path $pfxDir)) { New-Item -ItemType Directory -Path $pfxDir -Force | Out-Null }

        Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $securePwd -Force
        Write-Ok "PFX exported to: $PfxPath"
    }

    Write-Host "`nNext steps:" -ForegroundColor White
    Write-Host " - Upload the .cer file ($PublicCertPath) to your Azure App Registration -> Certificates & secrets -> Upload certificate." -ForegroundColor Cyan
    Write-Host " - In your appsettings.json set Authentication.CertificateThumbprint to the certificate thumbprint above." -ForegroundColor Cyan
    Write-Host " - If you exported a PFX for use on another machine, import it into the LocalMachine or CurrentUser store and grant access to the private key as needed." -ForegroundColor Cyan

    # Prepare return values compatible with older PowerShell versions
    $pfxOut = $null
    if ($ExportPfx) { $pfxOut = $PfxPath }

    return @{ Thumbprint = $thumbprint; PublicCertPath = $PublicCertPath; PfxPath = $pfxOut }

} catch {
    Write-WarnMsg "Failed to create or export certificate: $_"
    throw
}
