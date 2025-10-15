function Format-ComputerData {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$RawData
    )

    $formattedData = @()

    foreach ($computer in $RawData) {
        $formattedData += [PSCustomObject]@{
            ComputerName      = $computer.ComputerName
            DNSHostName       = $computer.DNSHostName
            IPv4Address       = $computer.IPv4Address
            OperatingSystem   = $computer.OperatingSystem
            OSVersion         = $computer.OSVersion
            LastLogon         = $computer.LastLogon.ToString("yyyy-MM-dd HH:mm:ss")
            Description       = $computer.Description
            LoggedInUser      = $computer.LoggedInUser
            DistinguishedName = $computer.DistinguishedName
        }
    }

    return $formattedData
}

export-modulemember -function Format-ComputerData