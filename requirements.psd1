@{
    'RequiredModules' = @(
        @{
            'ModuleName' = 'AzureAD'
            'ModuleVersion' = '2.0.2.140'
        },
        @{
            'ModuleName' = 'Microsoft.Graph'
            'ModuleVersion' = '1.9.0'
        },
        @{
            'ModuleName' = 'PSScriptAnalyzer'
            'ModuleVersion' = '1.19.0'
        }
    )
    'PowerShellVersion' = '5.1'
    'Description' = 'This file lists the required PowerShell modules and their versions for the Active Directory Computer Information Management System (IMS).'
}