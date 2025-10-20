#Requires -Modules ActiveDirectory

param(
    [string]$OutputPath = "C:\temp",
    [switch]$DetectiveMode,
    [switch]$NetworkDiscovery,
    [switch]$ShowList,
    [switch]$ExportToCsv
)

function Get-LocalADDevices {
    Write-Host "`n=== LOCAL ACTIVE DIRECTORY DISCOVERY ===" -ForegroundColor Cyan
    Write-Host "Running from inside the domain - this will show EVERYTHING!" -ForegroundColor Green
    
    # Get ALL computers from local AD (not Azure AD)
    $computers = Get-ADComputer -Filter * -Properties Name, OperatingSystem, OperatingSystemVersion, LastLogonDate, Description, DistinguishedName, DNSHostName, Enabled, IPv4Address, Location, ManagedBy, WhenCreated, WhenChanged
    
    Write-Host "Found $($computers.Count) computers in local Active Directory" -ForegroundColor Yellow
    
    $results = @()
    
    foreach ($computer in $computers) {
        # Try to get additional network info
        $pingable = $false
        $ipAddress = "Unknown"
        
        try {
            $pingResult = Test-Connection -ComputerName $computer.Name -Count 1 -Quiet -ErrorAction SilentlyContinue
            $pingable = $pingResult
            
            if ($pingable) {
                $resolvedIP = [System.Net.Dns]::GetHostAddresses($computer.Name) | Where-Object {$_.AddressFamily -eq 'InterNetwork'} | Select-Object -First 1
                if ($resolvedIP) {
                    $ipAddress = $resolvedIP.IPAddressToString
                }
            }
        } catch {
            # Continue silently
        }
        
        # Determine device type and importance
        $deviceType = "Unknown"
        $importance = "Low"
        $specialNotes = @()
        
        if ($computer.OperatingSystem -like "*Server*") {
            $deviceType = "Server"
            $importance = "High"
        } elseif ($computer.Name -match "(ADMIN|JUMP|GATE)") {
            $deviceType = "Administrative"
            $importance = "Critical"
            $specialNotes += "Potential Admin/Jump Device"
        } elseif ($computer.Name -match "(PCWA|BUCKHORN)") {
            $deviceType = "Infrastructure"
            $importance = "High"
            $specialNotes += "Core Infrastructure"
        } elseif ($computer.Name -match "(DESKTOP|LAPTOP|SURFACE)") {
            $deviceType = "Workstation"
            $importance = "Medium"
        }
        
        # Check for network equipment patterns
        if ($computer.Name -match "(SWITCH|ROUTER|FIREWALL|AP|WIFI)" -or 
            $computer.Description -match "(SWITCH|ROUTER|FIREWALL|ACCESS POINT)") {
            $deviceType = "Network Equipment"
            $importance = "Critical"
            $specialNotes += "Network Infrastructure"
        }
        
        # Analyze location hints
        $locationHint = "Unknown"
        if ($computer.DistinguishedName -match "OU=([^,]+)") {
            $locationHint = $matches[1]
        }
        
        $results += [PSCustomObject]@{
            ComputerName = $computer.Name
            DNSHostName = $computer.DNSHostName
            OperatingSystem = $computer.OperatingSystem
            OSVersion = $computer.OperatingSystemVersion
            LastLogonDate = $computer.LastLogonDate
            IsOnline = $pingable
            IPAddress = $ipAddress
            DeviceType = $deviceType
            Importance = $importance
            Description = $computer.Description
            Location = $computer.Location
            LocationHint = $locationHint
            SpecialNotes = ($specialNotes -join "; ")
            Enabled = $computer.Enabled
            WhenCreated = $computer.WhenCreated
            WhenChanged = $computer.WhenChanged
            DistinguishedName = $computer.DistinguishedName
            ManagedBy = $computer.ManagedBy
        }
        if ($ShowList) {
            $online = if ($pingable) { 'ONLINE' } else { 'OFFLINE' }
            Write-Host "  $online - $($computer.Name) - $ipAddress - $($computer.OperatingSystem)" -ForegroundColor Cyan
        }
    }
    
    return $results
}

function Get-NetworkEquipmentDiscovery {
    Write-Host "`n=== NETWORK EQUIPMENT DISCOVERY ===" -ForegroundColor Cyan
    
    # Get network configuration from current machine
    $networkConfig = Get-NetIPConfiguration
    $defaultGateway = $networkConfig.IPv4DefaultGateway.NextHop
    $subnet = ($networkConfig.IPv4Address.IPAddress -split '\.')[0..2] -join '.'
    
    Write-Host "Default Gateway: $defaultGateway" -ForegroundColor Yellow
    Write-Host "Scanning subnet: $subnet.0/24" -ForegroundColor Yellow
    
    $networkDevices = @()
    
    # Scan common network device IPs
    $commonIPs = @(1, 2, 3, 4, 5, 10, 11, 12, 20, 21, 22, 50, 100, 254)
    
    foreach ($lastOctet in $commonIPs) {
        $testIP = "$subnet.$lastOctet"
        Write-Host "Testing $testIP..." -NoNewline
        
        $pingResult = Test-Connection -ComputerName $testIP -Count 1 -Quiet -ErrorAction SilentlyContinue
        
        if ($pingResult) {
            Write-Host " ACTIVE" -ForegroundColor Green
            
            # Try to resolve hostname
            $hostname = "Unknown"
            try {
                $resolved = [System.Net.Dns]::GetHostEntry($testIP)
                $hostname = $resolved.HostName
            } catch {
                $hostname = "No reverse DNS"
            }
            
            # Check common management ports
            $managementPorts = @{
                80 = "HTTP"
                443 = "HTTPS"  
                22 = "SSH"
                23 = "Telnet"
                161 = "SNMP"
                8080 = "Alt HTTP"
            }
            
            $openPorts = @()
            foreach ($port in $managementPorts.Keys) {
                $portTest = Test-NetConnection -ComputerName $testIP -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
                if ($portTest) {
                    $openPorts += "$port ($($managementPorts[$port]))"
                }
            }
            
            $networkDevices += [PSCustomObject]@{
                IPAddress = $testIP
                Hostname = $hostname
                OpenPorts = ($openPorts -join ", ")
                DeviceType = if ($testIP -eq $defaultGateway) { "Default Gateway" } 
                           elseif ($openPorts -match "161") { "Managed Switch/Router" }
                           elseif ($openPorts -match "80|443") { "Managed Device" }
                           else { "Unknown Device" }
                IsGateway = ($testIP -eq $defaultGateway)
            }
        } else {
            Write-Host " No response" -ForegroundColor Gray
        }
    }
    
    return $networkDevices
}

function Get-DNSZoneAnalysis {
    Write-Host "`n=== DNS ZONE ANALYSIS ===" -ForegroundColor Cyan
    
    try {
        # Get DNS zones (only works on DNS server/DC)
        $dnsZones = Get-DnsServerZone -ErrorAction SilentlyContinue
        
        if ($dnsZones) {
            Write-Host "DNS Zones found:" -ForegroundColor Green
            $dnsZones | ForEach-Object {
                Write-Host "  Zone: $($_.ZoneName) (Type: $($_.ZoneType))" -ForegroundColor White
                
                # Look for interesting records in internal zones
                if ($_.ZoneName -notlike "*.arpa" -and $_.ZoneType -eq "Primary") {
                    try {
                        $records = Get-DnsServerResourceRecord -ZoneName $_.ZoneName -ErrorAction SilentlyContinue | 
                                  Where-Object { $_.HostName -match "(vpn|firewall|router|switch|gateway|admin|jump)" }
                        
                        if ($records) {
                            Write-Host "    Interesting records:" -ForegroundColor Yellow
                            $records | ForEach-Object {
                                Write-Host "      $($_.HostName) -> $($_.RecordData)" -ForegroundColor Cyan
                            }
                        }
                    } catch {
                        # Continue silently
                    }
                }
            }
        }
    } catch {
        Write-Host "DNS zone analysis not available (not running on DNS server)" -ForegroundColor Yellow
    }
}

try {
    Write-Host "=== BUCKHORN LOCAL AD DISCOVERY ===" -ForegroundColor Red
    Write-Host "Running from INSIDE the domain - this is the REAL inventory!" -ForegroundColor Green
    
    # Get local AD devices
    $devices = Get-LocalADDevices
    
    if ($NetworkDiscovery) {
        # Discover network equipment
        $networkEquipment = Get-NetworkEquipmentDiscovery
        
        # DNS analysis
        Get-DNSZoneAnalysis
    }
    
    if ($DetectiveMode) {
        Write-Host "`n=== DETECTIVE ANALYSIS ===" -ForegroundColor Red
        
        # Group by device type
        $deviceGroups = $devices | Group-Object DeviceType
        foreach ($group in $deviceGroups) {
            Write-Host "`n$($group.Name) Devices: $($group.Count)" -ForegroundColor Yellow
            $group.Group | Where-Object { $_.Importance -eq "Critical" -or $_.Importance -eq "High" } | 
                ForEach-Object {
                    $status = if ($_.IsOnline) { "🟢 ONLINE" } else { "🔴 OFFLINE" }
                    Write-Host "  $status $($_.ComputerName) ($($_.IPAddress))" -ForegroundColor White
                    if ($_.SpecialNotes) {
                        Write-Host "    Notes: $($_.SpecialNotes)" -ForegroundColor Cyan
                    }
                }
        }
        
        # Show potential targets
        $targets = $devices | Where-Object { 
            $_.ComputerName -match "(ADMIN|JUMP|GATE)" -or 
            $_.SpecialNotes -match "Admin" -or
            $_.Importance -eq "Critical"
        }
        
        if ($targets) {
            Write-Host "`n🎯 HIGH-VALUE TARGETS:" -ForegroundColor Red
            $targets | ForEach-Object {
                $status = if ($_.IsOnline) { "🟢" } else { "🔴" }
                Write-Host "  $status $($_.ComputerName) - $($_.IPAddress) - $($_.OperatingSystem)" -ForegroundColor White
            }
        }
    }
    
    if ($ExportToCsv) {
        $csvPath = Join-Path $OutputPath "LocalAD_Discovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $devices | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "`n💾 Results exported to: $csvPath" -ForegroundColor Green
        
        if ($NetworkDiscovery -and $networkEquipment) {
            $networkCsvPath = Join-Path $OutputPath "NetworkEquipment_Discovery_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $networkEquipment | Export-Csv -Path $networkCsvPath -NoTypeInformation
            Write-Host "💾 Network equipment exported to: $networkCsvPath" -ForegroundColor Green
        }
    }
    
} catch {
    Write-Error "Error during local AD discovery: $($_.Exception.Message)"
}