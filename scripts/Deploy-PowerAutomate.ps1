# This script deploys the necessary components to integrate with Power Automate, allowing for scheduled runs or triggers based on specific events.

# Define the necessary parameters for Power Automate deployment
$flowName = "ADComputerInfoFlow"
#$environmentName = "Default-8172f932-5feb-4c4e-af27-7ccadf81b8ba" # Change as necessary
$resourceGroupName = "YourResourceGroup" # Change as necessary
$location = "East US" # Change as necessary

# Authenticate to Azure
$azContext = Connect-AzAccount -ErrorAction Stop

# Create a new Power Automate flow
$flowDefinition = @{
    "name" = $flowName
    "type" = "Microsoft.Flow/flows"
    "location" = $location
    "properties" = @{
        "definition" = @{
            "$schema" = "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#"
            "actions" = @{
                "GetADComputerInfo" = @{
                    "inputs" = @{
                        "method" = "get"
                        "uri" = "https://graph.microsoft.com/v1.0/devices"
                    }
                    "runAfter" = @{}
                    "metadata" = @{
                        "operationMetadataId" = "GetADComputerInfo"
                    }
                    "type" = "Http"
                }
            }
            "triggers" = @{
                "Recurrence" = @{
                    "recurrence" = @{
                        "frequency" = "Day"
                        "interval" = 1
                    }
                    "type" = "Recurrence"
                }
            }
        }
        "parameters" = @{}
    }
}

# Deploy the flow
New-AzResource -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Flow/flows" -ResourceName $flowName -Location $location -Properties $flowDefinition

Write-Host "Power Automate flow '$flowName' has been deployed successfully."