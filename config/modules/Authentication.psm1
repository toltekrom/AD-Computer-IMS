function Get-GraphToken {
    param (
        [string]$clientId,
        [string]$clientSecret,
        [string]$tenantId
    )

    $body = @{
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }

    $uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body
        return $response.access_token
    } catch {
        Write-Error "Failed to retrieve access token: $_"
        return $null
    }
}

Export-ModuleMember -Function Get-GraphToken