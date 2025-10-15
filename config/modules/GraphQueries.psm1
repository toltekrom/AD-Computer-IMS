# File: /AD-Computer-IMS/AD-Computer-IMS/src/modules/GraphQueries.psm1

function Get-ComputerInfo {
    param (
        [string]$accessToken
    )

    $uri = "https://graph.microsoft.com/v1.0/devices"
    $headers = @{
        Authorization = "Bearer $accessToken"
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        return $response.value
    } catch {
        Write-Error "Failed to retrieve computer information from Microsoft Graph: $_"
        return $null
    }
}

function Get-ComputerDetails {
    param (
        [string]$computerId,
        [string]$accessToken
    )

    $uri = "https://graph.microsoft.com/v1.0/devices/$computerId"
    $headers = @{
        Authorization = "Bearer $accessToken"
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        return $response
    } catch {
        Write-Error "Failed to retrieve details for computer ID ${computerId}: $_"
        return $null
    }
}

Export-ModuleMember -Function Get-ComputerInfo, Get-ComputerDetails