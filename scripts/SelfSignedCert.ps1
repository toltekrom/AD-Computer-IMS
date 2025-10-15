# Create a self-signed certificate for Buckhorn
$cert = New-SelfSignedCertificate -Subject "CN=Buckhorn-ADComputer-IMS" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddMonths(12)

# Get the thumbprint
$thumbprint = $cert.Thumbprint
Write-Host "Certificate Thumbprint: $thumbprint" -ForegroundColor Green

# Export the certificate (public key) for Azure App Registration
$certPath = "C:\temp\Buckhorn-ADComputer-IMS.cer"
Export-Certificate -Cert $cert -FilePath $certPath
Write-Host "Certificate exported to: $certPath" -ForegroundColor Yellow