# Scripts

This folder contains helper scripts used by the AD-Computer-IMS project.

Files

- `Install-Dependencies.ps1` — Installs required PowerShell modules (Microsoft.Graph.*). Use this after cloning to ensure dependencies are present.
- `Create-SelfSignedCert.ps1` — Creates a self-signed certificate (default store: `Cert:\CurrentUser\My`), exports the public `.cer` to a chosen path, and optionally exports a password-protected `.pfx` for use on other machines. The script prints the certificate thumbprint that you should add to `config/appsettings.json` under `Authentication.CertificateThumbprint` and upload the `.cer` to your Azure App Registration under Certificates & secrets.
- `SelfSignedCert.ps1` — Simple legacy script that creates and exports a public `.cer` to `C:\temp` (kept for backwards compatibility).
- `Deploy-PowerAutomate.ps1` — Helper used for Power Automate deployment tasks.

- `Local-AD-Discovery.ps1` — Discovers local Active Directory computers and network equipment. Supports flags like `-DetectiveMode`, `-NetworkDiscovery`, `-ExportToCsv`, and the new `-ShowList` to print each discovered computer as they are processed.

Usage examples

Create a certificate and export the public certificate only:

```powershell
& '.\scripts\Create-SelfSignedCert.ps1' -Subject 'CN=AD-Computer-IMS' -ValidMonths 12 -Overwrite
```

Create a certificate and export a PFX for another machine (you will be prompted for a password):

```powershell
& '.\scripts\Create-SelfSignedCert.ps1' -Subject 'CN=AD-Computer-IMS' -ExportPfx -PfxPath 'C:\temp\AD-Computer-IMS.pfx' -Overwrite
```

Notes

- By default, `Create-SelfSignedCert.ps1` places the certificate in `Cert:\CurrentUser\My`. If you need the cert to live in the `LocalMachine` store (for services), import the PFX there and grant the appropriate private key permissions.
- Upload the `.cer` (public cert) to your App Registration -> Certificates & secrets -> Upload certificate. Use the thumbprint in `appsettings.json` to allow the script to authenticate with the certificate.
 
SharePoint integration notes

- The `Build-SharePointList.ps1` script uses Microsoft Graph to create lists and populate items. Your app registration must have appropriate application permissions, for example `Sites.ReadWrite.All` (application) to manage lists and items. After adding the permission in Azure Portal, grant admin consent.
- If using certificate-based auth, ensure the uploaded certificate is the public `.cer` from `Create-SelfSignedCert.ps1` and that the private key is present on the machine running the script.
- If you prefer delegated auth (interactive), ensure the signed-in user has permissions to the target SharePoint site.
