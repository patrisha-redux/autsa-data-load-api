# AUTSA Data Load API - Campus Snacks CSV Sync

This repository contains the Salesforce automation code for syncing Campus Snacks CSV data with Person Accounts in Salesforce.

## Overview

The Campus Snacks CSV sync automation downloads student data from the Campus Snacks API endpoint and upserts Person Account records in Salesforce. The system processes large datasets (30,000+ records) efficiently using Batch Apex and provides comprehensive logging and error tracking.

## Components

### Apex Classes

#### Main Classes
- **`CampusSnacksCSVDownloader`** - Handles CSV download, parsing, and utility methods
- **`CampusSnacksCSVBatch`** - Batch processing class for large datasets
- **`CampusSnacksCSVScheduler`** - Schedulable class for automated sync runs

#### Test Classes
- **`CampusSnacksCSVDownloader_Test`** - Test coverage for CSV downloader (84% coverage)
- **`CampusSnacksCSVBatch_Test`** - Test coverage for batch processing (82% coverage)
- **`CampusSnacksCSVScheduler_Test`** - Test coverage for scheduler (75% coverage)

### Metadata Components

#### Remote Site Settings
- **`Campus_Snacks_API`** - Allows HTTP callouts to `https://campus-snacks-production.up.railway.app`

#### Custom Settings
- **`CampusSnackAPI__c`** - Stores API configuration
  - `Endpoint__c` - API endpoint URL
  - `Token__c` - Bearer token for authentication

#### Custom Objects
- **`Data_Load_Sync_Logs__c`** - Tracks sync execution results
  - `Total_processed_records__c` - Total rows in CSV file
  - `Total_inserted_records__c` - New accounts created
  - `Total_updated_records__c` - Existing accounts updated
  - `Total_unprocessed_records__c` - Records with errors or skipped
  - `Error_messages__c` - Detailed error messages (format: `<StudentID> - <Error reason>`)

## Field Mappings

CSV fields are mapped to Salesforce Person Account fields as follows:

| CSV Field | Salesforce Field | Notes |
|-----------|-----------------|-------|
| StudentID | AccountNumber | Used as unique identifier for upsert |
| LegalFirstName | FirstName | Truncated to 40 chars if needed, remainder to Long_Name__pc |
| LegalFamilyName | LastName | |
| PrefFirstName | Preferred_first_name__pc | |
| Email | PersonEmail | Cleaned of invalid characters |
| AUTEmail | Alternative_Email__pc | Cleaned of invalid characters |
| - | Status__pc | Set to 'Active' |
| - | Last_verified_active_student__pc | Set to current date/time |

## Features

- **Batch Processing**: Handles large datasets (30,000+ records) without hitting governor limits
- **FirstName Truncation**: Automatically splits long first names (>40 chars) at the last space, moving remainder to `Long_Name__pc`
- **Email Cleaning**: Removes invalid characters from email addresses
- **AccountNumber Handling**: Intelligently handles AccountNumbers with/without leading zeros
- **Comprehensive Logging**: Creates `Data_Load_Sync_Logs__c` records after each sync with detailed statistics
- **Error Tracking**: Captures and logs all errors with StudentID and error reason
- **Schedulable**: Can be scheduled to run automatically on a recurring basis

## Setup Instructions

1. **Deploy Metadata**:
   ```bash
   sf project deploy start --source-dir force-app/main/default
   ```

2. **Configure Custom Setting**:
   - Navigate to Setup > Custom Settings
   - Find `CampusSnackAPI`
   - Create a new record with:
     - `Endpoint__c`: `https://campus-snacks-production.up.railway.app/api/download/active.csv`
     - `Token__c`: Your bearer token

3. **Run Initial Sync**:
   - See `HOW_TO_RUN_SYNC.md` for detailed instructions

## Usage

### Manual Execution

**Via Developer Console**:
```apex
Id jobId = CampusSnacksCSVDownloader.startBatchJob(200);
```

**Via Salesforce CLI**:
```bash
sf apex run --file scripts/apex/run-campus-snacks-batch.apex --target-org autsa-sandbox
```

### Scheduled Execution

**Via Setup UI**:
- Setup > Apex Classes > Schedule Apex
- Select `CampusSnacksCSVScheduler`
- Set your preferred schedule

**Via Developer Console**:
```apex
String cronExpression = '0 0 2 * * ?'; // Daily at 2 AM
Id scheduleId = System.schedule('Campus Snacks CSV Daily Sync', cronExpression, new CampusSnacksCSVScheduler());
```

## Monitoring

After each sync run, check:
- **Apex Jobs**: Setup > Apex Jobs (for batch job status)
- **Data Load Sync Logs**: Object tab or via SOQL query
- **Debug Logs**: Setup > Debug Logs (for detailed execution logs)

## Documentation

For detailed instructions on running the sync, troubleshooting, and understanding the sync logs, see:
- `HOW_TO_RUN_SYNC.md` - Complete guide on running and monitoring the sync

## Repository Structure

```
force-app/main/default/
├── classes/
│   ├── CampusSnacksCSVDownloader.cls
│   ├── CampusSnacksCSVBatch.cls
│   ├── CampusSnacksCSVScheduler.cls
│   └── [Test classes]
├── objects/
│   ├── CampusSnackAPI__c/
│   │   ├── CampusSnackAPI__c.object-meta.xml
│   │   └── fields/
│   │       ├── Endpoint__c.field-meta.xml
│   │       └── Token__c.field-meta.xml
│   └── Data_Load_Sync_Logs__c/
│       ├── Data_Load_Sync_Logs__c.object-meta.xml
│       ├── fields/
│       │   ├── Total_processed_records__c.field-meta.xml
│       │   ├── Total_inserted_records__c.field-meta.xml
│       │   ├── Total_updated_records__c.field-meta.xml
│       │   ├── Total_unprocessed_records__c.field-meta.xml
│       │   └── Error_messages__c.field-meta.xml
│       └── listViews/
└── remoteSiteSettings/
    └── Campus_Snacks_API.remoteSite-meta.xml
```

## Requirements

- Salesforce API Version: 64.0
- Person Accounts enabled
- Custom fields on Account:
  - `Preferred_first_name__pc`
  - `Alternative_Email__pc`
  - `Status__pc`
  - `Last_verified_active_student__pc`
  - `Long_Name__pc`

## Support

For issues or questions, refer to the sync logs in `Data_Load_Sync_Logs__c` object or check the debug logs in Salesforce Setup.
