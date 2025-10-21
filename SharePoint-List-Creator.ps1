#Requires -Modules PnP.PowerShell

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\appsettings.json"),
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory=$true)]
    [string]$SharePointSiteUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$ListName = "Buckhorn Device Inventory",
    
    [switch]$CreateList,
    [switch]$PopulateData,
    [switch]$UpdateExisting
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Connect-ToSharePoint {
    param([string]$SiteUrl)
    
    Write-Host "=== CONNECTING TO SHAREPOINT ===" -ForegroundColor Cyan
    
    try {
        # Connect using interactive login
        Connect-PnPOnline -Url $SharePointSiteUrl -ClientId $clientId -Tenant $tenantId -Thumbprint $thumbprint
        Write-Host "✅ Successfully connected to SharePoint" -ForegroundColor Green
        
        # Verify connection
        $web = Get-PnPWeb
        Write-Host "Connected to: $($web.Title)" -ForegroundColor Gray
        
        return $true
    } catch {
        Write-Error "Failed to connect to SharePoint: $($_.Exception.Message)"
        return $false
    }
}

function Get-CsvStructure {
    param([string]$FilePath)
    
    Write-Host "`n=== ANALYZING CSV STRUCTURE ===" -ForegroundColor Cyan
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "CSV file not found: $FilePath"
        return $null
    }
    
    try {
        # Read first few rows to understand structure
        $csvData = Import-Csv $FilePath | Select-Object -First 5
        $headers = ($csvData | Get-Member -MemberType NoteProperty).Name
        
        Write-Host "📊 CSV Analysis Results:" -ForegroundColor Yellow
        Write-Host "File: $FilePath" -ForegroundColor Gray
        Write-Host "Columns found: $($headers.Count)" -ForegroundColor Gray
        
        Write-Host "`n📋 Column Headers:" -ForegroundColor Yellow
        $headers | ForEach-Object { Write-Host "   • $_" -ForegroundColor White }
        
        Write-Host "`n📈 Sample Data (first row):" -ForegroundColor Yellow
        if ($csvData.Count -gt 0) {
            $csvData[0].PSObject.Properties | ForEach-Object {
                Write-Host "   $($_.Name): $($_.Value)" -ForegroundColor Gray
            }
        }
        
        return @{
            Headers = $headers
            SampleData = $csvData
            RowCount = (Import-Csv $FilePath).Count
        }
        
    } catch {
        Write-Error "Failed to analyze CSV: $($_.Exception.Message)"
        return $null
    }
}

function Create-SharePointList {
    param(
        [string]$ListName,
        [array]$CsvHeaders
    )
    
    Write-Host "`n=== CREATING SHAREPOINT LIST ===" -ForegroundColor Cyan
    
    try {
        # Check if list already exists
        $existingList = Get-PnPList -Identity $ListName -ErrorAction SilentlyContinue
        
        if ($existingList) {
            Write-Host "⚠️  List '$ListName' already exists!" -ForegroundColor Yellow
            $response = Read-Host "Do you want to update it? (y/n)"
            if ($response -ne 'y') {
                return $existingList
            }
        } else {
            # Create new list
            Write-Host "📝 Creating new list: $ListName" -ForegroundColor Yellow
            $newList = New-PnPList -Title $ListName -Template GenericList -Url $ListName.Replace(' ', '')
            Write-Host "✅ List created successfully" -ForegroundColor Green
        }
        
        # Define column mappings for device inventory
        $columnMappings = @{
            "ComputerName" = @{Type="Text"; DisplayName="Computer Name"}
            "DNSHostName" = @{Type="Text"; DisplayName="DNS Host Name"}
            "OperatingSystem" = @{Type="Choice"; DisplayName="Operating System"; Choices=@("Windows 10", "Windows 11", "Windows Server 2019", "Windows Server 2022", "Windows 7", "Linux", "macOS")}
            "OSVersion" = @{Type="Text"; DisplayName="OS Version"}
            "LastLogonDate" = @{Type="DateTime"; DisplayName="Last Logon Date"}
            "IsOnline" = @{Type="Boolean"; DisplayName="Is Online"}
            "IPAddress" = @{Type="Text"; DisplayName="IP Address"}
            "DeviceType" = @{Type="Choice"; DisplayName="Device Type"; Choices=@("Workstation", "Server", "Network Equipment", "Administrative", "Infrastructure")}
            "Importance" = @{Type="Choice"; DisplayName="Importance"; Choices=@("Low", "Medium", "High", "Critical")}
            "Description" = @{Type="Note"; DisplayName="Description"}
            "Location" = @{Type="Text"; DisplayName="Location"}
            "LocationHint" = @{Type="Text"; DisplayName="Location Hint"}
            "SpecialNotes" = @{Type="Note"; DisplayName="Special Notes"}
            "Enabled" = @{Type="Boolean"; DisplayName="Enabled"}
            "WhenCreated" = @{Type="DateTime"; DisplayName="When Created"}
            "WhenChanged" = @{Type="DateTime"; DisplayName="When Changed"}
            "DistinguishedName" = @{Type="Note"; DisplayName="Distinguished Name"}
            "ManagedBy" = @{Type="Text"; DisplayName="Managed By"}
        }
        
        # Create columns based on CSV headers
        Write-Host "`n📋 Creating columns..." -ForegroundColor Yellow
        
        foreach ($header in $CsvHeaders) {
            if ($columnMappings.ContainsKey($header)) {
                $colConfig = $columnMappings[$header]
                
                try {
                    # Check if column already exists
                    $existingField = Get-PnPField -List $ListName -Identity $header -ErrorAction SilentlyContinue
                    
                    if (-not $existingField) {
                        switch ($colConfig.Type) {
                            "Text" {
                                Add-PnPField -List $ListName -DisplayName $colConfig.DisplayName -InternalName $header -Type Text
                            }
                            "Note" {
                                Add-PnPField -List $ListName -DisplayName $colConfig.DisplayName -InternalName $header -Type Note
                            }
                            "DateTime" {
                                Add-PnPField -List $ListName -DisplayName $colConfig.DisplayName -InternalName $header -Type DateTime
                            }
                            "Boolean" {
                                Add-PnPField -List $ListName -DisplayName $colConfig.DisplayName -InternalName $header -Type Boolean
                            }
                            "Choice" {
                                Add-PnPField -List $ListName -DisplayName $colConfig.DisplayName -InternalName $header -Type Choice -Choices $colConfig.Choices
                            }
                        }
                        Write-Host "   ✅ Added column: $($colConfig.DisplayName)" -ForegroundColor Green
                    } else {
                        Write-Host "   ⚠️  Column exists: $($colConfig.DisplayName)" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "   ❌ Failed to create column $header`: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                # Create as generic text field
                try {
                    $existingField = Get-PnPField -List $ListName -Identity $header -ErrorAction SilentlyContinue
                    if (-not $existingField) {
                        Add-PnPField -List $ListName -DisplayName $header -InternalName $header -Type Text
                        Write-Host "   ✅ Added generic column: $header" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "   ❌ Failed to create column $header`: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        
        return Get-PnPList -Identity $ListName
        
    } catch {
        Write-Error "Failed to create SharePoint list: $($_.Exception.Message)"
        return $null
    }
}

function Import-CsvToSharePoint {
    param(
        [string]$ListName,
        [string]$CsvPath
    )
    
    Write-Host "`n=== IMPORTING CSV DATA TO SHAREPOINT ===" -ForegroundColor Cyan
    
    try {
        # Import CSV data
        $csvData = Import-Csv $CsvPath
        Write-Host "📊 Importing $($csvData.Count) records..." -ForegroundColor Yellow
        
        $successCount = 0
        $errorCount = 0
        
        foreach ($row in $csvData) {
            try {
                # Convert row to hashtable for SharePoint
                $listItem = @{}
                
                $row.PSObject.Properties | ForEach-Object {
                    $fieldName = $_.Name
                    $fieldValue = $_.Value
                    
                    # Handle special data types
                    switch ($fieldName) {
                        "LastLogonDate" {
                            if ($fieldValue -and $fieldValue -ne "Unknown" -and $fieldValue -ne "") {
                                try {
                                    $listItem[$fieldName] = [DateTime]::Parse($fieldValue)
                                } catch {
                                    $listItem[$fieldName] = $null
                                }
                            }
                        }
                        "WhenCreated" {
                            if ($fieldValue -and $fieldValue -ne "Unknown" -and $fieldValue -ne "") {
                                try {
                                    $listItem[$fieldName] = [DateTime]::Parse($fieldValue)
                                } catch {
                                    $listItem[$fieldName] = $null
                                }
                            }
                        }
                        "WhenChanged" {
                            if ($fieldValue -and $fieldValue -ne "Unknown" -and $fieldValue -ne "") {
                                try {
                                    $listItem[$fieldName] = [DateTime]::Parse($fieldValue)
                                } catch {
                                    $listItem[$fieldName] = $null
                                }
                            }
                        }
                        "IsOnline" {
                            $listItem[$fieldName] = if ($fieldValue -eq "True" -or $fieldValue -eq $true) { $true } else { $false }
                        }
                        "Enabled" {
                            $listItem[$fieldName] = if ($fieldValue -eq "True" -or $fieldValue -eq $true) { $true } else { $false }
                        }
                        default {
                            # Regular text field
                            if ($fieldValue -and $fieldValue.Length -lt 255) {
                                $listItem[$fieldName] = $fieldValue
                            } elseif ($fieldValue -and $fieldValue.Length -ge 255) {
                                # Truncate long text
                                $listItem[$fieldName] = $fieldValue.Substring(0, 254)
                            }
                        }
                    }
                }
                
                # Add Title field (required)
                $listItem["Title"] = $row.ComputerName ?? "Unknown Device"
                
                # Create list item
                Add-PnPListItem -List $ListName -Values $listItem | Out-Null
                $successCount++
                
                if ($successCount % 10 -eq 0) {
                    Write-Host "   📈 Imported $successCount records..." -ForegroundColor Gray
                }
                
            } catch {
                $errorCount++
                Write-Host "   ❌ Failed to import $($row.ComputerName): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        Write-Host "`n📊 IMPORT COMPLETE:" -ForegroundColor Green
        Write-Host "   ✅ Successfully imported: $successCount records" -ForegroundColor Green
        Write-Host "   ❌ Failed imports: $errorCount records" -ForegroundColor Red
        
    } catch {
        Write-Error "Failed to import CSV data: $($_.Exception.Message)"
    }
}

function Get-SharePointListUrl {
    param([string]$ListName, [string]$SiteUrl)
    
    $listUrl = "$SiteUrl/Lists/$($ListName.Replace(' ', ''))"
    Write-Host "`n🌐 SharePoint List URL:" -ForegroundColor Cyan
    Write-Host "$listUrl" -ForegroundColor Yellow
    
    return $listUrl
}

try {
    Write-Host "=== SHAREPOINT LIST CREATOR FROM CSV ===" -ForegroundColor Red
    Write-Host "🎯 Converting Device Inventory CSV to SharePoint List" -ForegroundColor Yellow
    
    # Analyze CSV structure
    $csvAnalysis = Get-CsvStructure -FilePath $CsvPath
    if (-not $csvAnalysis) {
        throw "Cannot proceed without valid CSV analysis"
    }
    
    Write-Host "`n📊 Ready to process $($csvAnalysis.RowCount) device records" -ForegroundColor Green
    
    # Connect to SharePoint
    $connected = Connect-ToSharePoint -SiteUrl $SharePointSiteUrl
    if (-not $connected) {
        throw "Cannot proceed without SharePoint connection"
    }
    
    if ($CreateList) {
        # Create the SharePoint list
        $list = Create-SharePointList -ListName $ListName -CsvHeaders $csvAnalysis.Headers
        if (-not $list) {
            throw "Failed to create SharePoint list"
        }
    }
    
    if ($PopulateData) {
        # Import CSV data to SharePoint
        Import-CsvToSharePoint -ListName $ListName -CsvPath $CsvPath
    }
    
    # Show final results
    $listUrl = Get-SharePointListUrl -ListName $ListName -SiteUrl $SharePointSiteUrl
    
    Write-Host "`n🎉 MISSION ACCOMPLISHED!" -ForegroundColor Green
    Write-Host "Your Buckhorn device inventory is now in SharePoint!" -ForegroundColor Cyan
    Write-Host "Access it at: $listUrl" -ForegroundColor Yellow
    
} catch {
    Write-Error "SharePoint list creation failed: $($_.Exception.Message)"
} finally {
    # Disconnect from SharePoint
    try {
        Disconnect-PnPOnline
        Write-Host "`n👋 Disconnected from SharePoint" -ForegroundColor Gray
    } catch {
        # Silent disconnect
    }
}