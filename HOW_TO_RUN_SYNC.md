# How to Run Campus Snacks CSV Sync

## ⚠️ IMPORTANT: Use Batch Class for Large Datasets

**For large CSV files (more than a few hundred records), use the Batch class to avoid CPU time limits:**

## Method 1: Batch Class (Recommended for Large Datasets) ⭐

### Option A: Using Helper Method (Easiest)

1. Log into your Salesforce sandbox
2. Open **Developer Console** (Setup → Developer Console)
3. Click **Debug** → **Open Execute Anonymous Window**
4. Paste this code:

```apex
// Start batch job - processes 200 records per batch
Id jobId = CampusSnacksCSVDownloader.startBatchJob(200);
System.debug('Batch job started with ID: ' + jobId);
```

5. Check **"Open Log"** checkbox
6. Click **Execute**
7. Monitor the batch job:
   - Go to **Setup** → **Apex Jobs** (or search for "Apex Jobs")
   - Find your job and monitor its progress
   - Check the debug logs for detailed results

### Option B: Direct Batch Execution

```apex
CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
Id jobId = Database.executeBatch(batch, 200); // 200 records per batch
System.debug('Batch job started with ID: ' + jobId);
```

## Method 2: Synchronous Method (Small Datasets Only)

**⚠️ WARNING: Only use for small CSV files (< 1000 records). For larger files, use the Batch class above.**

1. Log into your Salesforce sandbox
2. Open **Developer Console** (Setup → Developer Console)
3. Click **Debug** → **Open Execute Anonymous Window**
4. Paste this code:

```apex
CampusSnacksCSVDownloader.UpsertResult result = CampusSnacksCSVDownloader.downloadAndUpsertAccounts();

System.debug('=== Campus Snacks Sync Results ===');
System.debug('Success: ' + result.success);
System.debug('Processed: ' + result.processedCount);
System.debug('Created: ' + result.createdCount);
System.debug('Updated: ' + result.updatedCount);
System.debug('Message: ' + result.message);

if (result.success) {
    System.debug('✓ Sync completed successfully!');
} else {
    System.debug('✗ Sync failed: ' + result.message);
}
```

5. Check **"Open Log"** checkbox
6. Click **Execute**
7. View the results in the Log tab

## Method 3: Salesforce CLI

### For Batch Job:
```bash
cd "/Users/patrishaperez/Documents/REDUX/Project/Autsa Partial/Autsa Partial"
sf apex run --file scripts/apex/run-campus-snacks-batch.apex --target-org autsa-sandbox
```

### For Synchronous (small datasets only):
```bash
cd "/Users/patrishaperez/Documents/REDUX/Project/Autsa Partial/Autsa Partial"
sf apex run --file scripts/apex/run-campus-snacks-sync.apex --target-org autsa-sandbox
```

## Method 4: VS Code with Salesforce Extensions

1. Open the file: `scripts/apex/run-campus-snacks-sync.apex`
2. Right-click in the editor
3. Select **"SFDX: Execute Anonymous Apex"**
4. Select your org (autsa-sandbox)

## Method 5: Schedule It (Automated) ⭐ Recommended for Regular Syncs

The sync can now be scheduled to run automatically on a recurring basis.

### Option A: Schedule via Developer Console

1. Open **Developer Console** (Setup → Developer Console)
2. Click **Debug** → **Open Execute Anonymous Window**
3. Paste this code:

```apex
// Schedule to run daily at 2:00 AM
String cronExpression = '0 0 2 * * ?';
String jobName = 'Campus Snacks CSV Daily Sync';
Id scheduleId = System.schedule(jobName, cronExpression, new CampusSnacksCSVScheduler());
System.debug('Schedule ID: ' + scheduleId);
System.debug('Job scheduled successfully!');
```

4. Check **"Open Log"** checkbox
5. Click **Execute**
6. Verify the schedule:
   - Go to **Setup** → **Scheduled Jobs** (search for "Scheduled Jobs")
   - You should see your scheduled job with the next run time

### Option B: Schedule via Salesforce Setup UI

1. Go to **Setup** → **Apex Classes** (search for "Apex Classes")
2. Click **Schedule Apex** button
3. Configure:
   - **Job Name**: Enter a name (e.g., "Campus Snacks CSV Daily Sync")
   - **Apex Class**: Select `CampusSnacksCSVScheduler`
   - **Frequency**: Choose your preferred schedule (Daily, Weekly, Monthly, etc.)
   - **Start Time**: Set the time you want the job to run
4. Click **Save**

### Cron Expression Examples

If scheduling via Developer Console, customize the cron expression:

- **Daily at 2:00 AM**: `'0 0 2 * * ?'`
- **Every weekday at 2:00 AM**: `'0 0 2 ? * MON-FRI'`
- **First day of every month at 2:00 AM**: `'0 0 2 1 * ?'`
- **Every 6 hours**: `'0 0 */6 * * ?'`
- **Every Monday at 3:00 AM**: `'0 0 3 ? * MON'`

### Monitoring Scheduled Jobs

- **View Scheduled Jobs**: Setup → Scheduled Jobs
- **View Batch Executions**: Setup → Apex Jobs (shows actual batch job runs)
- **View Sync Logs**: Navigate to **Data Load Sync Logs** object (each sync creates a log record)

## What the Sync Does

- Downloads CSV from: `https://campus-snacks-production.up.railway.app/api/download/active.csv`
- Maps fields:
  - StudentID → AccountNumber
  - LegalFirstName → FirstName (truncates to 40 chars, remainder to Long_Name__pc)
  - LegalFamilyName → LastName
  - PrefFirstName → Preferred_first_name__pc
  - Email → PersonEmail (cleaned of invalid characters)
  - AUTEmail → Alternative_Email__pc (cleaned of invalid characters)
- Upserts Person Accounts:
  - **New accounts**: Creates with all mapped fields + Status__pc = 'Active' + Last_verified_active_student__pc = Now
  - **Existing accounts**: Updates Last_verified_active_student__pc = Now and Status__pc = 'Active'
- Creates a log record in **Data Load Sync Logs** object after each sync completion

## Classes Used in the Sync Process

The Campus Snacks CSV sync uses three main Apex classes that work together to download, process, and sync data. Understanding these classes helps with troubleshooting and customization.

### 1. CampusSnacksCSVDownloader

**Purpose**: Core utility class that handles CSV download, parsing, and data transformation operations.

**Key Responsibilities**:
- Downloads CSV file from the Campus Snacks API endpoint using HTTP callout
- Parses CSV content into structured data (maps)
- Provides helper methods for CSV line splitting and field parsing
- Handles FirstName truncation logic (splits names longer than 40 characters)
- Cleans email addresses (removes invalid characters)
- Provides a convenient method to start batch jobs

**Main Methods**:
- `downloadActiveCSV()`: Downloads the CSV file from the API endpoint
  - Returns: `CSVResponse` object with success status, CSV content, and error message
  - Uses Bearer token authentication
  - Handles HTTP errors and exceptions

- `splitIntoLines(String content)`: Splits CSV content into individual lines
  - Avoids regex to prevent "Regex too complicated" errors with large files
  - Uses character-by-character iteration for efficiency

- `parseCSVLine(String line)`: Parses a single CSV line into field values
  - Handles quoted fields and escaped characters
  - Returns: List of field values

- `parseCSVToMaps(String csvContent)`: Converts entire CSV into list of maps
  - First row becomes headers (keys)
  - Subsequent rows become data records (values)
  - Returns: `List<Map<String, String>>` where each map represents a CSV row

- `splitFirstNameIfTooLong(String firstName, Integer maxLength)`: Truncates FirstName if needed
  - Finds the last space before the 40-character limit
  - Returns: Map with 'firstName' (truncated) and 'longName' (remainder)
  - Used to prevent "data value too large" errors

- `cleanEmailAddress(String email)`: Removes invalid characters from email addresses
  - Keeps only valid email characters (letters, numbers, @, ., -, _, +)
  - Removes non-ASCII and control characters
  - Returns: Cleaned email string

- `startBatchJob(Integer batchSize)`: Convenience method to start batch processing
  - Creates and executes `CampusSnacksCSVBatch` instance
  - Returns: Batch job ID
  - Default batch size: 200 records

**When to Use**:
- Direct CSV download operations
- Synchronous processing for small datasets (< 1000 records)
- Utility methods for CSV parsing and data transformation

**Dependencies**:
- Requires Remote Site Setting: `Campus_Snacks_API` (allows callouts to the API endpoint)

---

### 2. CampusSnacksCSVBatch

**Purpose**: Batchable class that processes large CSV files in chunks to avoid Salesforce governor limits.

**Key Responsibilities**:
- Downloads CSV file in the `start()` method
- Splits CSV into batches for processing
- Parses CSV rows and maps fields to Salesforce Account fields
- Performs upsert operations (insert new accounts, update existing ones)
- Tracks processing statistics (created, updated, failed, skipped)
- Creates log records in Data Load Sync Logs object
- Handles errors gracefully and collects error messages

**Interfaces Implemented**:
- `Database.Batchable<String>`: Processes CSV lines as String objects
- `Database.AllowsCallouts`: Allows HTTP callouts in the `start()` method
- `Database.Stateful`: Maintains state across batch executions (counters, errors)

**Main Methods**:
- `start(Database.BatchableContext bc)`: Initializes the batch job
  - Downloads CSV file from API
  - Splits CSV into lines (doesn't parse yet to save CPU)
  - Extracts CSV headers
  - Returns: `Iterable<String>` of CSV data lines (excluding header)
  - Throws exception if CSV download fails or Person Account record type not found

- `execute(Database.BatchableContext bc, List<String> scope)`: Processes a batch of CSV lines
  - Parses each line into a map (using headers from `start()`)
  - Queries existing Person Accounts for the current batch
  - Maps CSV fields to Account fields:
    - StudentID → AccountNumber
    - LegalFirstName → FirstName (with truncation if > 40 chars)
    - LegalFamilyName → LastName
    - PrefFirstName → Preferred_first_name__pc
    - Email → PersonEmail (cleaned)
    - AUTEmail → Alternative_Email__pc (cleaned)
  - Handles AccountNumber matching (with/without leading zeros)
  - Creates new accounts or updates existing ones
  - Sets `Status__pc = 'Active'` and `Last_verified_active_student__pc = Now`
  - Tracks statistics and collects errors

- `finish(Database.BatchableContext bc)`: Finalizes the batch job
  - Logs summary statistics to debug logs
  - Creates a record in Data Load Sync Logs object with:
    - Total processed records
    - Total inserted records
    - Total updated records
    - Total unprocessed records
    - Error messages (formatted as `<StudentID> - <Error reason>`)

**State Variables** (maintained across batches):
- `processedCount`: Total rows processed
- `createdCount`: New accounts created
- `updatedCount`: Existing accounts updated
- `successCount`: Successful DML operations
- `failCount`: Failed DML operations
- `skippedCount`: Rows skipped (blank StudentID)
- `errors`: List of error messages
- `totalRows`: Total data rows in CSV

**When to Use**:
- Processing large CSV files (> 1000 records)
- Scheduled automated syncs
- Any sync that might hit CPU time limits

**Best Practices**:
- Recommended batch size: 200 records per batch
- Monitor via Setup → Apex Jobs
- Check Data Load Sync Logs for results

---

### 3. CampusSnacksCSVScheduler

**Purpose**: Schedulable class that enables automated, recurring sync operations.

**Key Responsibilities**:
- Implements `Schedulable` interface for Salesforce scheduler
- Triggers batch job execution on schedule
- Provides error handling for scheduled executions

**Main Methods**:
- `execute(SchedulableContext sc)`: Called by Salesforce scheduler
  - Starts the batch job using `CampusSnacksCSVDownloader.startBatchJob(200)`
  - Logs batch job ID for tracking
  - Handles exceptions gracefully (logs errors, doesn't crash)

**When to Use**:
- Automated daily, weekly, or monthly syncs
- Regular data synchronization without manual intervention
- Production environments requiring consistent data updates

**How to Schedule**:
1. **Via Developer Console**:
   ```apex
   System.schedule('Job Name', '0 0 2 * * ?', new CampusSnacksCSVScheduler());
   ```

2. **Via Setup UI**:
   - Setup → Apex Classes → Schedule Apex
   - Select `CampusSnacksCSVScheduler`
   - Configure frequency and time

**Dependencies**:
- Requires `CampusSnacksCSVDownloader` class (calls `startBatchJob()`)
- The batch job (`CampusSnacksCSVBatch`) is executed automatically

---

### Class Interaction Flow

```
┌─────────────────────────┐
│ CampusSnacksCSVScheduler │ (Optional - for scheduled runs)
│                         │
│ execute()               │
└───────────┬─────────────┘
            │
            │ Calls
            ▼
┌─────────────────────────┐
│ CampusSnacksCSVDownloader│
│                         │
│ startBatchJob()         │
└───────────┬─────────────┘
            │
            │ Creates & Executes
            ▼
┌─────────────────────────┐
│ CampusSnacksCSVBatch    │
│                         │
│ start()                 │ → Downloads CSV via CampusSnacksCSVDownloader
│   │                     │
│   ├─→ execute()        │ → Processes batches (uses helper methods)
│   │                     │
│   └─→ finish()         │ → Creates log record
└─────────────────────────┘
```

**For Manual Runs**:
- Developer Console → Execute Anonymous → `CampusSnacksCSVDownloader.startBatchJob(200)`
- This directly creates and executes `CampusSnacksCSVBatch`

**For Scheduled Runs**:
- Scheduler → `CampusSnacksCSVScheduler.execute()` → `CampusSnacksCSVDownloader.startBatchJob()` → `CampusSnacksCSVBatch`

---

### Key Design Decisions

1. **Batch Processing**: Large CSV files are processed in batches to avoid CPU time limits
2. **Stateful Batch**: Statistics are maintained across batches for accurate final reporting
3. **Separate Parsing**: CSV parsing happens in `execute()` method, not `start()`, to distribute CPU usage
4. **Error Collection**: All errors are collected and logged in the finish method
5. **AccountNumber Matching**: Handles both with and without leading zeros for existing records
6. **Email Cleaning**: Removes invalid characters to prevent validation errors
7. **FirstName Truncation**: Automatically splits long names to prevent field length errors

## Data Load Sync Logs Object

After each sync run (whether manual or scheduled), a log record is automatically created in the **Data Load Sync Logs** (`Data_Load_Sync_Logs__c`) object. This provides a complete audit trail of all sync operations.

### Object Details
- **Object API Name**: `Data_Load_Sync_Logs__c`
- **Object Label**: Data Load Sync Logs
- **Purpose**: Track and audit all Campus Snacks CSV sync operations

### Fields

| Field API Name | Field Label | Type | Description |
|---------------|-------------|------|-------------|
| `Total_processed_records__c` | Total Processed Records | Number | Total number of rows found in the CSV file (excluding header). This represents all data rows that were attempted to be processed. |
| `Total_inserted_records__c` | Total Inserted Records | Number | Total number of new Person Account records successfully created during the sync. |
| `Total_updated_records__c` | Total Updated Records | Number | Total number of existing Person Account records successfully updated during the sync. |
| `Total_unprocessed_records__c` | Total Unprocessed Records | Number | Total number of records that were not successfully processed. This includes:<br>- Records with blank StudentID (skipped)<br>- Records that failed during DML operations (insert/update errors) |
| `Error_messages__c` | Error Messages | Long Text Area | Detailed error messages for all unprocessed records. Each error follows the format:<br>`<StudentID> - <Error reason>`<br><br>Examples:<br>- `666668 - Blank StudentID`<br>- `25334976 - First Name: data value too large`<br>- `17969691 - Email: invalid email address` |

### How to View Sync Logs

1. **Navigate to the Object**:
   - In Salesforce, go to the App Launcher (9-dot menu)
   - Search for "Data Load Sync Logs"
   - Click on the object

2. **View Log Records**:
   - Each sync run creates a new log record
   - Records are sorted by Created Date (most recent first)
   - Click on a record to view all details

3. **Analyze Results**:
   - Check `Total_processed_records__c` to see how many rows were in the CSV
   - Compare `Total_inserted_records__c` + `Total_updated_records__c` with `Total_processed_records__c` to verify all records were processed
   - Review `Error_messages__c` to identify any issues that need attention
   - If `Total_unprocessed_records__c` > 0, investigate the errors in `Error_messages__c`

### Use Cases

- **Audit Trail**: Track when syncs ran and their results
- **Error Analysis**: Identify patterns in failed records
- **Performance Monitoring**: Compare sync results over time
- **Data Quality**: Identify data issues in the source CSV (invalid emails, missing StudentIDs, etc.)
- **Compliance**: Maintain records of data synchronization activities

### Example Log Record

After a sync, you might see a log record like:
- **Total Processed Records**: 30,000
- **Total Inserted Records**: 500
- **Total Updated Records**: 29,200
- **Total Unprocessed Records**: 300
- **Error Messages**: Contains 300 error entries, one per unprocessed record

## Troubleshooting

If you encounter errors:
- Check the debug logs in Developer Console
- Verify the Remote Site Setting is active
- Ensure the API endpoint is accessible
- Check that Person Account record type exists
