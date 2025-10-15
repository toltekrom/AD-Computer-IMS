param(
    [string]$Query = "all",
    [string]$Format = "json"
)

# Import the main script from the same directory
$scriptPath = Join-Path $PSScriptRoot "AD-Computer-IMS.ps1"

try {
    switch ($Query.ToLower()) {
        "all" {
            $data = & $scriptPath -ReturnJson
        }
        "compliant" {
            $data = & $scriptPath -ReturnJson
            $devices = $data | ConvertFrom-Json | Where-Object { $_.IsCompliant -eq $true }
            $data = $devices | ConvertTo-Json -Depth 3
        }
        "noncompliant" {
            $data = & $scriptPath -ReturnJson
            $devices = $data | ConvertFrom-Json | Where-Object { $_.IsCompliant -eq $false }
            $data = $devices | ConvertTo-Json -Depth 3
        }
        "managed" {
            $data = & $scriptPath -ReturnJson
            $devices = $data | ConvertFrom-Json | Where-Object { $_.IsManaged -eq $true }
            $data = $devices | ConvertTo-Json -Depth 3
        }
        default {
            $data = & $scriptPath -ReturnJson
        }
    }
    
    # Return data in requested format
    if ($Format -eq "csv") {
        $devices = $data | ConvertFrom-Json
        $csvOutput = $devices | ConvertTo-Csv -NoTypeInformation
        Write-Output $csvOutput
    } else {
        Write-Output $data
    }
    
} catch {
    $errorResponse = @{
        Error = $true
        Message = $_.Exception.Message
        Timestamp = Get-Date
    } | ConvertTo-Json
    
    Write-Output $errorResponse
}