/**
 * @description Batchable class to process Campus Snacks CSV and upsert Person Accounts.
 * Processes CSV data in batches to avoid CPU time limits and governor restrictions.
 * Implements Database.Stateful to maintain statistics across batch executions.
 * 
 * @author Salesforce Development Team
 * @date 2024
 * 
 * @note This class runs in system context (without sharing) to ensure all operations succeed.
 * CRUD/FLS checks are not performed as this is a system integration requiring full access.
 * 
 * Usage:
 * CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
 * Database.executeBatch(batch, 200); // Process 200 rows per batch
 */
public without sharing class CampusSnacksCSVBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {
    
    private Integer processedCount = 0;
    private Integer createdCount = 0;
    private Integer updatedCount = 0;
    private Integer successCount = 0;
    private Integer failCount = 0;
    private Integer skippedCount = 0; // Rows skipped due to blank StudentID
    private List<String> errors = new List<String>();
    private Id personAccountRecordTypeId;
    private Map<String, Account> existingAccountsByNumber;
    private DateTime now;
    private List<String> csvHeaders;
    private Integer totalRows = 0;
    private Integer totalCSVLines = 0;
    
    /**
     * @description Start method - downloads CSV and splits into lines for batch processing.
     * Does not parse CSV lines yet to save CPU time. Parsing happens in execute() method.
     * @param bc The BatchableContext provided by the platform
     * @return Iterable<String> of CSV data lines (excluding header row)
     * @throws BatchException if CSV download fails or Person Account record type not found
     */
    public Iterable<String> start(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'Starting Campus Snacks CSV Batch');
        
        // Get Person Account record type ID
        personAccountRecordTypeId = getPersonAccountRecordTypeId();
        if (personAccountRecordTypeId == null) {
            throw new BatchException('Person Account record type not found');
        }
        
        // Download CSV
        CampusSnacksCSVDownloader.CSVResponse csvResponse = CampusSnacksCSVDownloader.downloadActiveCSV();
        if (!csvResponse.success) {
            throw new BatchException('Failed to download CSV: ' + csvResponse.errorMessage);
        }
        
        // Split into lines (don't parse yet to save CPU)
        List<String> lines = CampusSnacksCSVDownloader.splitIntoLines(csvResponse.csvContent);
        totalCSVLines = lines.size();
        
        System.debug(LoggingLevel.INFO, '===== CSV Download Summary =====');
        System.debug(LoggingLevel.INFO, 'Total lines in CSV (including header): ' + totalCSVLines);
        System.debug(LoggingLevel.INFO, 'CSV content size: ' + csvResponse.csvContent.length() + ' characters');
        
        if (lines.size() < 2) {
            System.debug(LoggingLevel.ERROR, 'ERROR: No data rows found in CSV (only ' + lines.size() + ' line(s))');
            return new List<String>();
        }
        
        // Store header row
        csvHeaders = CampusSnacksCSVDownloader.parseCSVLine(lines[0]);
        System.debug(LoggingLevel.INFO, 'CSV Headers (' + csvHeaders.size() + ' columns): ' + csvHeaders);
        
        // Return data lines only (skip header)
        List<String> dataLines = new List<String>();
        Integer emptyLineCount = 0;
        for (Integer i = 1; i < lines.size(); i++) {
            if (String.isNotBlank(lines[i])) {
                dataLines.add(lines[i]);
            } else {
                emptyLineCount++;
            }
        }
        
        totalRows = dataLines.size();
        System.debug(LoggingLevel.INFO, '===== CSV Processing Summary =====');
        System.debug(LoggingLevel.INFO, 'Total CSV lines: ' + totalCSVLines);
        System.debug(LoggingLevel.INFO, 'Header row: 1');
        System.debug(LoggingLevel.INFO, 'Data rows (non-empty): ' + totalRows);
        System.debug(LoggingLevel.INFO, 'Empty rows skipped: ' + emptyLineCount);
        System.debug(LoggingLevel.INFO, 'Total rows to process: ' + totalRows);
        
        // Pre-query existing accounts - collect account numbers from first batch only
        // We'll query accounts as needed in execute method to avoid CPU limits
        existingAccountsByNumber = new Map<String, Account>();
        
        now = DateTime.now();
        
        return dataLines;
    }
    
    /**
     * @description Execute method - processes a batch of CSV lines.
     * Parses CSV lines, queries existing accounts, maps fields, and performs DML operations.
     * This method is called once per batch by the platform.
     * @param bc The BatchableContext provided by the platform
     * @param scope List of CSV data lines to process in this batch
     */
    public void execute(Database.BatchableContext bc, List<String> scope) {
        System.debug(LoggingLevel.INFO, '===== Processing Batch =====');
        System.debug(LoggingLevel.INFO, 'Batch size (lines received): ' + scope.size());
        
        // Parse lines into maps
        List<Map<String, String>> rows = new List<Map<String, String>>();
        Integer parseErrors = 0;
        for (String line : scope) {
            if (String.isBlank(line)) {
                continue;
            }
            try {
                List<String> values = CampusSnacksCSVDownloader.parseCSVLine(line);
                Map<String, String> row = new Map<String, String>();
                for (Integer j = 0; j < csvHeaders.size(); j++) {
                    String header = csvHeaders[j].trim();
                    String value = j < values.size() ? values[j].trim() : '';
                    row.put(header, value);
                }
                rows.add(row);
            } catch (Exception e) {
                parseErrors++;
                System.debug(LoggingLevel.ERROR, 'Error parsing CSV line: ' + e.getMessage());
            }
        }
        
        System.debug(LoggingLevel.INFO, 'Successfully parsed rows: ' + rows.size());
        if (parseErrors > 0) {
            System.debug(LoggingLevel.WARN, 'Rows with parse errors: ' + parseErrors);
        }
        
        // Collect account numbers for this batch (include both with and without leading zero)
        Set<String> batchAccountNumbers = new Set<String>();
        Set<String> batchAccountNumbersWithZero = new Set<String>();
        for (Map<String, String> row : rows) {
            String accountNumber = row.get('StudentID');
            if (String.isNotBlank(accountNumber)) {
                accountNumber = accountNumber.trim();
                batchAccountNumbers.add(accountNumber);
                // Also add version with leading zero for querying
                if (!accountNumber.startsWith('0')) {
                    batchAccountNumbersWithZero.add('0' + accountNumber);
                }
            }
        }
        
        // Combine both sets for query
        Set<String> allAccountNumbersToQuery = new Set<String>();
        allAccountNumbersToQuery.addAll(batchAccountNumbers);
        allAccountNumbersToQuery.addAll(batchAccountNumbersWithZero);
        
        // Query existing accounts for this batch only
        // Note: CRUD/FLS checks not performed - system context requires full access
        Map<String, Account> batchExistingAccounts = new Map<String, Account>();
        if (!allAccountNumbersToQuery.isEmpty()) {
            for (Account acc : [
                SELECT Id, AccountNumber, FirstName, LastName, PersonEmail,
                       Preferred_first_name__pc, Alternative_Email__pc, 
                       Status__pc, Last_verified_active_student__pc
                FROM Account
                WHERE AccountNumber IN :allAccountNumbersToQuery
                AND IsPersonAccount = true
            ]) {
                if (String.isNotBlank(acc.AccountNumber)) {
                    // Store by the actual AccountNumber from Salesforce
                    batchExistingAccounts.put(acc.AccountNumber, acc);
                    // Also store by normalized version (without leading zero) for lookup
                    String normalizedNumber = acc.AccountNumber;
                    if (normalizedNumber.startsWith('0') && normalizedNumber.length() > 1) {
                        normalizedNumber = normalizedNumber.substring(1);
                    }
                    if (!batchExistingAccounts.containsKey(normalizedNumber)) {
                        batchExistingAccounts.put(normalizedNumber, acc);
                    }
                }
            }
        }
        
        // Merge with existing accounts map
        existingAccountsByNumber.putAll(batchExistingAccounts);
        
        List<Account> accountsToInsert = new List<Account>();
        List<Account> accountsToUpdate = new List<Account>();
        
        for (Map<String, String> row : rows) {
            try {
                String accountNumber = row.get('StudentID');
                
                // Skip if AccountNumber is blank
                if (String.isBlank(accountNumber)) {
                    skippedCount++;
                    String errorMsg = 'Unknown - Blank StudentID';
                    errors.add(errorMsg);
                    System.debug(LoggingLevel.WARN, 'Skipping row with blank StudentID. Row data: ' + row);
                    continue;
                }
                
                accountNumber = accountNumber.trim();
                
                Account acc;
                Boolean isNew = false;
                
                // Check if account exists
                if (batchExistingAccounts.containsKey(accountNumber)) {
                    acc = batchExistingAccounts.get(accountNumber);
                    isNew = false;
                    updatedCount++;
                } else {
                    acc = new Account();
                    acc.RecordTypeId = personAccountRecordTypeId;
                    acc.AccountNumber = accountNumber;
                    isNew = true;
                    createdCount++;
                }
                
                // Map CSV fields to Salesforce fields (trim once for efficiency)
                String legalFirstName = String.isNotBlank(row.get('LegalFirstName')) ? row.get('LegalFirstName').trim() : null;
                String legalFamilyName = String.isNotBlank(row.get('LegalFamilyName')) ? row.get('LegalFamilyName').trim() : null;
                String prefFirstName = String.isNotBlank(row.get('PrefFirstName')) ? row.get('PrefFirstName').trim() : null;
                String email = String.isNotBlank(row.get('Email')) ? cleanEmailAddress(row.get('Email').trim()) : null;
                String autEmail = String.isNotBlank(row.get('AUTEmail')) ? cleanEmailAddress(row.get('AUTEmail').trim()) : null;
                
                // For new accounts, set all fields
                if (isNew) {
                    if (String.isNotBlank(legalFirstName)) {
                        // Handle FirstName truncation if more than 40 characters
                        Map<String, String> firstNameSplit = CampusSnacksCSVDownloader.splitFirstNameIfTooLong(legalFirstName, 40);
                        acc.FirstName = firstNameSplit.get('firstName');
                        if (String.isNotBlank(firstNameSplit.get('longName'))) {
                            acc.Long_Name__pc = firstNameSplit.get('longName');
                        }
                    }
                    if (String.isNotBlank(legalFamilyName)) {
                        acc.LastName = legalFamilyName;
                    }
                    if (String.isNotBlank(prefFirstName)) {
                        acc.Preferred_first_name__pc = prefFirstName;
                    }
                    if (String.isNotBlank(email)) {
                        acc.PersonEmail = email;
                    }
                    if (String.isNotBlank(autEmail)) {
                        acc.Alternative_Email__pc = autEmail;
                    }
                    acc.Status__pc = 'Active';
                } else {
                    // For existing accounts, only update specific fields if they changed
                    if (String.isNotBlank(legalFirstName) && acc.FirstName != legalFirstName) {
                        // Handle FirstName truncation if more than 40 characters (for updates too)
                        Map<String, String> firstNameSplit = CampusSnacksCSVDownloader.splitFirstNameIfTooLong(legalFirstName, 40);
                        acc.FirstName = firstNameSplit.get('firstName');
                        if (String.isNotBlank(firstNameSplit.get('longName'))) {
                            acc.Long_Name__pc = firstNameSplit.get('longName');
                        }
                    }
                    if (String.isNotBlank(legalFamilyName) && acc.LastName != legalFamilyName) {
                        acc.LastName = legalFamilyName;
                    }
                    if (String.isNotBlank(prefFirstName) && acc.Preferred_first_name__pc != prefFirstName) {
                        acc.Preferred_first_name__pc = prefFirstName;
                    }
                    if (String.isNotBlank(email) && acc.PersonEmail != email) {
                        acc.PersonEmail = email;
                    }
                    if (String.isNotBlank(autEmail) && acc.Alternative_Email__pc != autEmail) {
                        acc.Alternative_Email__pc = autEmail;
                    }
                }
                
                // Always update these fields for both new and existing
                acc.Last_verified_active_student__pc = now;
                acc.Status__pc = 'Active';
                
                if (isNew) {
                    accountsToInsert.add(acc);
                } else {
                    accountsToUpdate.add(acc);
                }
                
                processedCount++;
                
            } catch (Exception e) {
                String studentID = String.isNotBlank(row.get('StudentID')) ? row.get('StudentID') : 'Unknown';
                String errorMsg = studentID + ' - ' + e.getMessage();
                errors.add(errorMsg);
                failCount++;
                System.debug(LoggingLevel.ERROR, errorMsg);
            }
        }
        
        // Perform insert and update operations
        System.debug(LoggingLevel.INFO, 'Accounts to INSERT (new): ' + accountsToInsert.size());
        System.debug(LoggingLevel.INFO, 'Accounts to UPDATE (existing): ' + accountsToUpdate.size());
        
        if (!accountsToInsert.isEmpty()) {
            // Perform DML in system context (allOrNone=false to allow partial success)
            // Note: CRUD/FLS checks not performed - system integration requires full access
            Database.SaveResult[] insertResults = Database.insert(accountsToInsert, false);
            
            Integer insertSuccess = 0;
            Integer insertFail = 0;
            for (Integer i = 0; i < insertResults.size(); i++) {
                Database.SaveResult result = insertResults[i];
                if (result.isSuccess()) {
                    successCount++;
                    insertSuccess++;
                } else {
                    failCount++;
                    insertFail++;
                    String accountNumber = accountsToInsert[i].AccountNumber;
                    String errorMsg = accountNumber + ' - ';
                    List<String> errorMessages = new List<String>();
                    for (Database.Error err : result.getErrors()) {
                        errorMessages.add(err.getMessage());
                    }
                    errorMsg += String.join(errorMessages, '; ');
                    errors.add(errorMsg);
                    System.debug(LoggingLevel.ERROR, errorMsg);
                }
            }
            System.debug(LoggingLevel.INFO, 'Insert results - Success: ' + insertSuccess + ', Failed: ' + insertFail);
        }
        
        if (!accountsToUpdate.isEmpty()) {
            // Perform DML in system context (allOrNone=false to allow partial success)
            // Note: CRUD/FLS checks not performed - system integration requires full access
            Database.SaveResult[] updateResults = Database.update(accountsToUpdate, false);
            
            Integer updateSuccess = 0;
            Integer updateFail = 0;
            for (Integer i = 0; i < updateResults.size(); i++) {
                Database.SaveResult result = updateResults[i];
                if (result.isSuccess()) {
                    successCount++;
                    updateSuccess++;
                } else {
                    failCount++;
                    updateFail++;
                    String accountNumber = accountsToUpdate[i].AccountNumber;
                    String errorMsg = accountNumber + ' - ';
                    List<String> errorMessages = new List<String>();
                    for (Database.Error err : result.getErrors()) {
                        errorMessages.add(err.getMessage());
                    }
                    errorMsg += String.join(errorMessages, '; ');
                    errors.add(errorMsg);
                    System.debug(LoggingLevel.ERROR, errorMsg);
                }
            }
            System.debug(LoggingLevel.INFO, 'Update results - Success: ' + updateSuccess + ', Failed: ' + updateFail);
        }
        
        System.debug(LoggingLevel.INFO, 'Batch completed - Processed: ' + processedCount + ', Created: ' + createdCount + ', Updated: ' + updatedCount);
    }
    
    /**
     * @description Finish method - logs final results and creates sync log record.
     * Called once after all batches complete. Creates a record in Data_Load_Sync_Logs__c object.
     * @param bc The BatchableContext provided by the platform
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '===== Campus Snacks CSV Batch Completed =====');
        System.debug(LoggingLevel.INFO, '===== SUMMARY =====');
        System.debug(LoggingLevel.INFO, 'Total CSV rows (from file): ' + totalRows);
        System.debug(LoggingLevel.INFO, 'Total CSV lines (including header): ' + totalCSVLines);
        System.debug(LoggingLevel.INFO, 'Rows processed: ' + processedCount);
        System.debug(LoggingLevel.INFO, 'Rows skipped (blank StudentID): ' + skippedCount);
        System.debug(LoggingLevel.INFO, 'New accounts created (INSERT): ' + createdCount);
        System.debug(LoggingLevel.INFO, 'Existing accounts updated (UPDATE): ' + updatedCount);
        System.debug(LoggingLevel.INFO, 'Successfully upserted: ' + successCount);
        System.debug(LoggingLevel.INFO, 'Failed: ' + failCount);
        System.debug(LoggingLevel.INFO, '=====');
        
        // Calculate difference
        Integer expectedProcessed = totalRows;
        Integer actualProcessed = processedCount + skippedCount;
        if (expectedProcessed != actualProcessed) {
            System.debug(LoggingLevel.WARN, 'WARNING: Expected to process ' + expectedProcessed + ' rows, but processed ' + actualProcessed);
            System.debug(LoggingLevel.WARN, 'Difference: ' + (expectedProcessed - actualProcessed) + ' rows may not have been processed');
        }
        
        if (!errors.isEmpty()) {
            System.debug(LoggingLevel.ERROR, '===== ERRORS (' + errors.size() + ') =====');
            // Limit error output to first 50 to avoid log size issues
            Integer errorLimit = Math.min(50, errors.size());
            for (Integer i = 0; i < errorLimit; i++) {
                System.debug(LoggingLevel.ERROR, 'Error ' + (i + 1) + ': ' + errors[i]);
            }
            if (errors.size() > 50) {
                System.debug(LoggingLevel.ERROR, '... and ' + (errors.size() - 50) + ' more errors (check full logs)');
            }
        }
        
        System.debug(LoggingLevel.INFO, '===== END SUMMARY =====');
        
        // Create sync log record
        createSyncLog();
    }
    
    /**
     * @description Creates a Data Load Sync Log record after sync completion.
     * Logs all statistics including processed, inserted, updated, and unprocessed record counts.
     * Also includes formatted error messages for troubleshooting.
     */
    private void createSyncLog() {
        try {
            // Calculate total unprocessed records (skipped + failed)
            Integer totalUnprocessed = skippedCount + failCount;
            
            // Format error messages (limit to 131,072 characters for Long Text Area)
            String errorMessagesText = '';
            if (!errors.isEmpty()) {
                List<String> formattedErrors = new List<String>();
                for (String error : errors) {
                    formattedErrors.add(error);
                }
                errorMessagesText = String.join(formattedErrors, '\n');
                
                // Truncate if too long (Long Text Area max is 131,072 characters)
                if (errorMessagesText.length() > 131072) {
                    errorMessagesText = errorMessagesText.substring(0, 131000) + '\n... (truncated, ' + (errors.size() - 1) + ' more errors)';
                }
            }
            
            // Create the log record
            // Note: CRUD/FLS checks not performed - system context requires full access
            SObject syncLog = Schema.getGlobalDescribe().get('Data_Load_Sync_Logs__c').newSObject();
            syncLog.put('Total_processed_records__c', totalRows);
            syncLog.put('Total_inserted_records__c', createdCount);
            syncLog.put('Total_updated_records__c', updatedCount);
            syncLog.put('Total_unprocessed_records__c', totalUnprocessed);
            syncLog.put('Error_messages__c', errorMessagesText);
            
            Database.SaveResult result = Database.insert(syncLog, false);
            
            if (result.isSuccess()) {
                System.debug(LoggingLevel.INFO, 'Sync log record created successfully with ID: ' + result.getId());
            } else {
                System.debug(LoggingLevel.ERROR, 'Failed to create sync log record:');
                for (Database.Error err : result.getErrors()) {
                    System.debug(LoggingLevel.ERROR, '  - ' + err.getMessage());
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating sync log record: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        }
    }
    
    /**
     * @description Retrieves the Person Account record type ID.
     * Queries for the first Person Account record type found in the org.
     * @return RecordTypeId for Person Account, or null if not found or error occurs
     */
    private Id getPersonAccountRecordTypeId() {
        try {
            // Query for Person Account record type
            // Note: CRUD/FLS checks not performed - system context requires full access
            RecordType personAccountRecordType = [
                SELECT Id, Name, DeveloperName, SobjectType
                FROM RecordType
                WHERE SobjectType = 'Account'
                AND IsPersonType = true
                LIMIT 1
            ];
            
            return personAccountRecordType.Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error finding Person Account record type: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Cleans email address by removing invalid characters.
     * Removes non-ASCII characters, control characters, and other invalid email characters.
     * Keeps only letters, numbers, @, ., -, _, and + characters.
     * Performs basic email validation (must contain @ and . after @).
     * @param email The email address to clean
     * @return Cleaned email address in lowercase, or null if invalid or blank
     */
    private String cleanEmailAddress(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        
        email = email.trim();
        
        // Remove invalid characters (non-ASCII, control characters, etc.)
        // Keep only: letters, numbers, @, ., -, _, +
        String cleanedEmail = '';
        for (Integer i = 0; i < email.length(); i++) {
            String currentChar = email.substring(i, i + 1);
            Integer charCode = currentChar.charAt(0);
            
            // Allow: letters (a-z, A-Z), numbers (0-9), @, ., -, _, +
            if ((charCode >= 48 && charCode <= 57) ||  // 0-9
                (charCode >= 65 && charCode <= 90) ||  // A-Z
                (charCode >= 97 && charCode <= 122) || // a-z
                currentChar == '@' || currentChar == '.' || currentChar == '-' || currentChar == '_' || currentChar == '+') {
                cleanedEmail += currentChar;
            }
        }
        
        // Basic email validation - must have @ and at least one . after @
        if (String.isBlank(cleanedEmail) || !cleanedEmail.contains('@')) {
            return null;
        }
        
        String[] parts = cleanedEmail.split('@');
        if (parts.size() != 2 || String.isBlank(parts[0]) || String.isBlank(parts[1])) {
            return null;
        }
        
        if (!parts[1].contains('.')) {
            return null;
        }
        
        return cleanedEmail.toLowerCase();
    }
    
    /**
     * @description Custom exception class for batch processing errors.
     * Used to throw meaningful error messages during batch initialization.
     */
    public class BatchException extends Exception {}
}
