#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Sites, ImportExcel

param(
    [string]$ConfigPath = "E:\Users\jerom\source\AD-Computer-IMS\config\appsettings.json",
    [string]$ExcelFilePath = "E:\Users\jerom\source\AzureAD_UserAudit2.xlsx",
    [string]$SharePointSiteUrl = "https://pcwabuckhorn.sharepoint.com/sites/SecOps",
    [string]$ListName = "Devices",
    [switch]$AnalyzeOnly,
    [switch]$CreateList,
    [switch]$PopulateData
)

# Import configuration
$config = Get-Content $ConfigPath | ConvertFrom-Json
$clientId = $config.Authentication.ClientId
$tenantId = $config.Authentication.TenantId
$thumbprint = $config.Authentication.CertificateThumbprint

function Test-ExcelFile {
    param([string]$FilePath)
    
    Write-Host "`n=== ANALYZING EXCEL FILE ===" -ForegroundColor Cyan
    Write-Host "File Path: $FilePath" -ForegroundColor Gray
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "❌ Excel file not found!" -ForegroundColor Red
        return $null
    }
    
    try {
        # Import Excel data to analyze structure
        $excelData = Import-Excel -Path $FilePath -WorksheetName 1
        
        Write-Host "✅ Excel file loaded successfully!" -ForegroundColor Green
        Write-Host "   Total Rows: $($excelData.Count)" -ForegroundColor White
        
        # Get column names
        $columns = $excelData[0].PSObject.Properties.Name
        Write-Host "   Columns Found: $($columns.Count)" -ForegroundColor White
        
        Write-Host "`n📋 COLUMN STRUCTURE:" -ForegroundColor Yellow
        foreach ($column in $columns) {
            $sampleValue = $excelData[0].$column
            $dataType = if ($sampleValue -match '^\d{4}-\d{2}-\d{2}') { 'DateTime' } 
                       elseif ($sampleValue -match '^\d+$') { 'Number' }
                       elseif ($sampleValue -match '^(true|false)$') { 'Boolean' }
                       else { 'Text' }
            
            Write-Host "   • $column ($dataType): $sampleValue" -ForegroundColor Gray
        }
        
        return @{
            Data = $excelData
            Columns = $columns
            RowCount = $excelData.Count
        }
        
    } catch {
        Write-Host "❌ Error reading Excel file: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-SharePointSite {
    param([string]$SiteUrl)
    
    Write-Host "`n=== CONNECTING TO SHAREPOINT SITE ===" -ForegroundColor Cyan
    
    try {
        # Extract site details from URL
        $siteUrlParts = $SiteUrl -replace 'https://', '' -split '/'
        $hostname = $siteUrlParts[0]
        $sitePath = '/' + ($siteUrlParts[1..($siteUrlParts.Length-1)] -join '/')
        
        Write-Host "Hostname: $hostname" -ForegroundColor Gray
        Write-Host "Site Path: $sitePath" -ForegroundColor Gray
        
        # Get the SharePoint site
        $site = Get-MgSite -Search "SecOps"
        
        if ($site) {
            Write-Host "✅ SharePoint site found!" -ForegroundColor Green
            Write-Host "   Site ID: $($site.Id)" -ForegroundColor Gray
            Write-Host "   Display Name: $($site.DisplayName)" -ForegroundColor Gray
            Write-Host "   Web URL: $($site.WebUrl)" -ForegroundColor Gray
            return $site
        } else {
            Write-Host "❌ SharePoint site not found" -ForegroundColor Red
            return $null
        }
        
    } catch {
        Write-Host "❌ Error connecting to SharePoint: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Create-SharePointList {
    param(
        [object]$Site,
        [string]$ListName,
        [array]$Columns
    )
    
    Write-Host "`n=== CREATING SHAREPOINT LIST ===" -ForegroundColor Cyan
    Write-Host "List Name: $ListName" -ForegroundColor Yellow
    
    try {
        # Check if list already exists
        $existingLists = Get-MgSiteList -SiteId $Site.Id
        $existingList = $existingLists | Where-Object { $_.DisplayName -eq $ListName }
        
        if ($existingList) {
            Write-Host "⚠️  List '$ListName' already exists!" -ForegroundColor Yellow
            Write-Host "   List ID: $($existingList.Id)" -ForegroundColor Gray
            return $existingList
        }
        
        # Create new list
        $listParams = @{
            DisplayName = $ListName
            Template = "genericList"
        }
        
        $newList = New-MgSiteList -SiteId $Site.Id -BodyParameter $listParams
        
        Write-Host "✅ List created successfully!" -ForegroundColor Green
        Write-Host "   List ID: $($newList.Id)" -ForegroundColor Gray
        
        # Add custom columns based on Excel structure
        Write-Host "`n📋 ADDING CUSTOM COLUMNS:" -ForegroundColor Yellow
        
        foreach ($column in $Columns) {
            if ($column -notin @('Title', 'ID', 'Created', 'Modified')) {
                try {
                    # Determine column type
                    $columnType = "text"  # Default to text
                    
                    $columnParams = @{
                        Name = $column
                        Text = @{ }
                    }
                    
                    $newColumn = New-MgSiteListColumn -SiteId $Site.Id -ListId $newList.Id -BodyParameter $columnParams
                    Write-Host "   ✅ Added column: $column" -ForegroundColor Green
                    
                } catch {
                    Write-Host "   ❌ Failed to add column '$column': $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        
        return $newList
        
    } catch {
        Write-Host "❌ Error creating SharePoint list: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Populate-SharePointList {
    param(
        [object]$Site,
        [object]$List,
        [array]$Data
    )
    
    Write-Host "`n=== POPULATING SHAREPOINT LIST ===" -ForegroundColor Cyan
    Write-Host "Records to import: $($Data.Count)" -ForegroundColor Yellow
    
    $successCount = 0
    $errorCount = 0
    
    foreach ($record in $Data) {
        try {
            # Prepare fields for SharePoint list item
            $fields = @{
                Title = $record.PSObject.Properties.Value | Select-Object -First 1  # Use first column as title
            }
            
            # Add all other fields
            foreach ($property in $record.PSObject.Properties) {
                if ($property.Name -ne 'Title' -and $property.Value) {
                    $fields[$property.Name] = $property.Value.ToString()
                }
            }
            
            # Create list item
            $listItemParams = @{
                Fields = $fields
            }
            
            $newItem = New-MgSiteListItem -SiteId $Site.Id -ListId $List.Id -BodyParameter $listItemParams
            $successCount++
            
            if ($successCount % 10 -eq 0) {
                Write-Host "   Imported $successCount records..." -ForegroundColor Gray
            }
            
        } catch {
            $errorCount++
            Write-Host "   ❌ Error importing record: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "`n✅ IMPORT COMPLETE!" -ForegroundColor Green
    Write-Host "   Successful: $successCount" -ForegroundColor White
    Write-Host "   Errors: $errorCount" -ForegroundColor White
}

try {
    Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    
    # Step 1: Analyze Excel file
    $excelAnalysis = Test-ExcelFile -FilePath $ExcelFilePath
    
    if (-not $excelAnalysis) {
        Write-Host "❌ Cannot proceed without valid Excel file" -ForegroundColor Red
        exit 1
    }
    
    if ($AnalyzeOnly) {
        Write-Host "`n=== ANALYSIS COMPLETE ===" -ForegroundColor Green
        Write-Host "Use -CreateList switch to create SharePoint list" -ForegroundColor Yellow
        Write-Host "Use -PopulateData switch to populate with data" -ForegroundColor Yellow
        exit 0
    }
    
    # Step 2: Connect to SharePoint site
    $sharePointSite = Get-SharePointSite -SiteUrl $SharePointSiteUrl
    
    if (-not $sharePointSite) {
        Write-Host "❌ Cannot proceed without SharePoint site access" -ForegroundColor Red
        exit 1
    }
    
    # Step 3: Create SharePoint list
    if ($CreateList) {
        $devicesList = Create-SharePointList -Site $sharePointSite -ListName $ListName -Columns $excelAnalysis.Columns
        
        if (-not $devicesList) {
            Write-Host "❌ Cannot proceed without creating list" -ForegroundColor Red
            exit 1
        }
    }
    
    # Step 4: Populate data
    if ($PopulateData) {
        # Get the existing list if we didn't just create it
        if (-not $devicesList) {
            $existingLists = Get-MgSiteList -SiteId $sharePointSite.Id
            $devicesList = $existingLists | Where-Object { $_.DisplayName -eq $ListName }
        }
        
        if ($devicesList) {
            Populate-SharePointList -Site $sharePointSite -List $devicesList -Data $excelAnalysis.Data
        } else {
            Write-Host "❌ Devices list not found. Use -CreateList first." -ForegroundColor Red
        }
    }
    
    Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Run with -AnalyzeOnly to see Excel structure" -ForegroundColor Yellow
    Write-Host "2. Run with -CreateList to create SharePoint list" -ForegroundColor Yellow
    Write-Host "3. Run with -PopulateData to import Excel data" -ForegroundColor Yellow
    Write-Host "4. Visit your SharePoint site to view the Devices list" -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to process Excel to SharePoint: $($_.Exception.Message)"
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}