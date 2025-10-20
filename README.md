# Active Directory Computer Information Management System (IMS)

## Overview
The Active Directory Computer Information Management System (IMS) is a PowerShell-based project designed to aggregate and manage computer information from Active Directory using Microsoft Graph API. This system allows for daily execution or can be triggered via Power Automate, providing flexibility in data management and reporting.

## Project Structure
```
AD-Computer-IMS
├── src
│   ├── AD-Computer-IMS.ps1          # Main script for aggregating AD computer information
│   ├── modules
│   │   ├── Authentication.psm1      # Module for handling authentication with Microsoft Graph
│   │   ├── GraphQueries.psm1        # Module for querying Microsoft Graph for computer information
│   │   └── DataProcessing.psm1      # Module for processing and formatting data
│   └── config
│       └── appsettings.json          # Configuration file for app registration credentials
├── scripts
│   ├── Install-Dependencies.ps1      # Script to install required dependencies
│   └── Deploy-PowerAutomate.ps1      # Script to deploy components for Power Automate integration
├── output
│   └── .gitkeep                      # Keeps the output directory in version control
├── logs
│   └── .gitkeep                      # Keeps the logs directory in version control
├── requirements.psd1                 # Lists required PowerShell modules and versions
└── README.md                         # Documentation for the project
```

## Scripts

See `scripts/README.md` for details about helper scripts (dependency installer, certificate helpers, deployment helpers).


## Setup Instructions
1. **Clone the Repository**: Clone this repository to your local machine.
2. **Configure App Registration**: Update the `src/config/appsettings.json` file with your Microsoft Graph app registration credentials (client ID, tenant ID, client secret).
3. **Install Dependencies**: Run the `scripts/Install-Dependencies.ps1` script to install any required PowerShell modules.
4. **Run the Main Script**: Execute the `src/AD-Computer-IMS.ps1` script to start aggregating computer information from Active Directory.

## Usage
- The main script can be scheduled to run daily using Task Scheduler or triggered via Power Automate for real-time data aggregation.
- Ensure that the app registration has the necessary permissions to access computer information in Microsoft Graph.

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License
This project is licensed under the MIT License. See the LICENSE file for more details.