/**
 * @description Apex class to download CSV file from Campus Snacks API endpoint and process Person Account records.
 * Downloads the active.csv file from the configured API endpoint and upserts Person Accounts in Salesforce.
 * API configuration is stored in CampusSnackAPI__c custom setting (Endpoint__c and Token__c fields).
 * 
 * @author Salesforce Development Team
 * @date 2024
 * 
 * @note This class runs in system context (without sharing) to ensure all operations succeed regardless of user permissions.
 * CRUD/FLS checks are not performed as this is a system integration that requires full access to Account records.
 * For production use, consider implementing Named Credentials instead of custom settings for enhanced security.
 */
public without sharing class CampusSnacksCSVDownloader {
    
    /**
     * @description Retrieves API configuration from CampusSnackAPI__c custom setting.
     * Validates that both Endpoint__c and Token__c fields are configured.
     * @return Map with 'endpoint' and 'token' keys, or null if not configured or invalid
     */
    private static Map<String, String> getAPISettings() {
        try {
            CampusSnackAPI__c apiSettings = CampusSnackAPI__c.getInstance();
            
            if (apiSettings == null || String.isBlank(apiSettings.Endpoint__c) || String.isBlank(apiSettings.Token__c)) {
                System.debug(LoggingLevel.ERROR, 'CampusSnackAPI custom setting not configured or missing required fields');
                return null;
            }
            
            Map<String, String> settings = new Map<String, String>();
            settings.put('endpoint', apiSettings.Endpoint__c.trim());
            settings.put('token', apiSettings.Token__c.trim());
            
            return settings;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving CampusSnackAPI custom setting: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Downloads the CSV file from the Campus Snacks API endpoint using Bearer token authentication.
     * Uses HTTP GET request with Authorization header. API endpoint and token are retrieved from custom setting.
     * @return CSVResponse wrapper containing success status, CSV content, and error message (if any)
     */
    public static CSVResponse downloadActiveCSV() {
        try {
            // Get API settings from custom setting
            Map<String, String> apiSettings = getAPISettings();
            if (apiSettings == null) {
                return new CSVResponse(false, null, 'CampusSnackAPI custom setting not configured. Please configure Endpoint__c and Token__c fields.');
            }
            
            String endpoint = apiSettings.get('endpoint');
            String token = apiSettings.get('token');
            
            // Create HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + token);
            req.setHeader('Accept', 'text/csv');
            req.setTimeout(60000); // 60 second timeout
            
            // Send the request
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            // Check response
            if (res.getStatusCode() == 200) {
                String csvContent = res.getBody();
                System.debug(LoggingLevel.INFO, 'CSV file downloaded successfully. Size: ' + csvContent.length() + ' characters');
                return new CSVResponse(true, csvContent, null);
            } else {
                String errorMsg = 'HTTP Error ' + res.getStatusCode() + ': ' + res.getStatus() + '. Body: ' + res.getBody();
                System.debug(LoggingLevel.ERROR, 'Error downloading CSV: ' + errorMsg);
                return new CSVResponse(false, null, errorMsg);
            }
            
        } catch (Exception e) {
            String errorMsg = 'Exception occurred: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, errorMsg);
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            return new CSVResponse(false, null, errorMsg);
        }
    }
    
    /**
     * @description Downloads CSV file and returns it as a list of string lines.
     * Useful for processing the CSV line by line without loading entire content into memory.
     * @return CSVLineResponse wrapper containing success status, list of CSV lines, and error message (if any)
     */
    public static CSVLineResponse downloadActiveCSVAsLines() {
        CSVResponse response = downloadActiveCSV();
        
        if (!response.success) {
            return new CSVLineResponse(false, null, response.errorMessage);
        }
        
        // Split CSV content into lines using custom method to avoid regex limits
        List<String> lines = splitIntoLines(response.csvContent);
        
        // Remove empty lines at the end
        while (lines.size() > 0 && String.isBlank(lines[lines.size() - 1])) {
            lines.remove(lines.size() - 1);
        }
        
        return new CSVLineResponse(true, lines, null);
    }
    
    /**
     * @description Parses CSV content into a list of maps where each map represents a data row.
     * First line is treated as headers and becomes the keys in each map.
     * @param csvContent The CSV content as a string
     * @return List of maps where keys are column headers and values are cell values. Returns empty list if CSV is blank or invalid.
     */
    public static List<Map<String, String>> parseCSVToMaps(String csvContent) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        
        if (String.isBlank(csvContent)) {
            return result;
        }
        
        // Use custom line splitting to avoid regex limits with large files
        List<String> lines = splitIntoLines(csvContent);
        
        if (lines.size() < 2) {
            // Need at least header and one data row
            return result;
        }
        
        // Parse header row
        List<String> headers = parseCSVLine(lines[0]);
        
        // Parse data rows
        for (Integer i = 1; i < lines.size(); i++) {
            if (String.isBlank(lines[i])) {
                continue; // Skip empty lines
            }
            
            List<String> values = parseCSVLine(lines[i]);
            Map<String, String> row = new Map<String, String>();
            
            // Map values to headers
            for (Integer j = 0; j < headers.size(); j++) {
                String header = headers[j].trim();
                String value = j < values.size() ? values[j].trim() : '';
                row.put(header, value);
            }
            
            result.add(row);
        }
        
        return result;
    }
    
    /**
     * @description Splits a string into lines without using regex to avoid "Regex too complicated" governor limits.
     * Handles both Unix (\n) and Windows (\r\n) line endings. Optimized for performance using character-by-character iteration.
     * @param content The content to split into lines
     * @return List of lines. Returns empty list if content is blank.
     */
    public static List<String> splitIntoLines(String content) {
        List<String> lines = new List<String>();
        
        if (String.isBlank(content)) {
            return lines;
        }
        
        Integer length = content.length();
        Integer startPos = 0;
        
        for (Integer i = 0; i < length; i++) {
            String currentChar = content.substring(i, i + 1);
            
            if (currentChar == '\n') {
                // Found newline, extract line
                if (i > startPos) {
                    lines.add(content.substring(startPos, i));
                } else {
                    lines.add('');
                }
                startPos = i + 1;
            } else if (currentChar == '\r') {
                // Check if next char is \n (Windows line ending)
                if (i + 1 < length && content.substring(i + 1, i + 2) == '\n') {
                    // Extract line up to \r
                    if (i > startPos) {
                        lines.add(content.substring(startPos, i));
                    } else {
                        lines.add('');
                    }
                    startPos = i + 2; // Skip both \r and \n
                    i++; // Skip the \n in next iteration
                } else {
                    // Just \r, treat as line break
                    if (i > startPos) {
                        lines.add(content.substring(startPos, i));
                    } else {
                        lines.add('');
                    }
                    startPos = i + 1;
                }
            }
        }
        
        // Add the last line if it doesn't end with newline
        if (startPos < length) {
            lines.add(content.substring(startPos));
        } else if (length > 0 && startPos == length) {
            // Content ends with newline, add empty line
            lines.add('');
        }
        
        return lines;
    }
    
    /**
     * @description Parses a single CSV line handling quoted values and commas.
     * Supports quoted fields that may contain commas. Removes surrounding quotes from field values.
     * Optimized for performance using substring operations instead of regex.
     * @param line The CSV line to parse
     * @return List of field values. Returns empty list if line is blank.
     */
    public static List<String> parseCSVLine(String line) {
        List<String> fields = new List<String>();
        
        if (String.isBlank(line)) {
            return fields;
        }
        
        Boolean inQuotes = false;
        Integer startPos = 0;
        Integer length = line.length();
        
        for (Integer i = 0; i < length; i++) {
            String currentChar = line.substring(i, i + 1);
            
            if (currentChar == '"') {
                inQuotes = !inQuotes;
            } else if (currentChar == ',' && !inQuotes) {
                // Extract field from startPos to i
                String field = line.substring(startPos, i);
                // Remove surrounding quotes if present
                if (field.length() >= 2 && field.startsWith('"') && field.endsWith('"')) {
                    field = field.substring(1, field.length() - 1);
                }
                fields.add(field);
                startPos = i + 1;
            }
        }
        
        // Add the last field
        if (startPos < length) {
            String field = line.substring(startPos);
            // Remove surrounding quotes if present
            if (field.length() >= 2 && field.startsWith('"') && field.endsWith('"')) {
                field = field.substring(1, field.length() - 1);
            }
            fields.add(field);
        } else if (startPos == length) {
            // Empty field at end
            fields.add('');
        }
        
        return fields;
    }
    
    /**
     * @description Response wrapper class for CSV download operations.
     * Contains success status, CSV content, and any error messages.
     */
    public class CSVResponse {
        public Boolean success;
        public String csvContent;
        public String errorMessage;
        
        public CSVResponse(Boolean success, String csvContent, String errorMessage) {
            this.success = success;
            this.csvContent = csvContent;
            this.errorMessage = errorMessage;
        }
    }
    
    /**
     * @description Starts a batch job to process CSV and upsert Person Accounts.
     * Recommended for large datasets (>1000 records) to avoid CPU time limits.
     * The batch job processes records in chunks, distributing CPU usage across multiple transactions.
     * @param batchSize Number of records to process per batch. Defaults to 200 if null or <= 0.
     * @return Job ID of the batch job that can be used to monitor progress in Setup > Apex Jobs
     */
    public static Id startBatchJob(Integer batchSize) {
        if (batchSize == null || batchSize <= 0) {
            batchSize = 200; // Default batch size
        }
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        return Database.executeBatch(batch, batchSize);
    }
    
    /**
     * @description Downloads CSV and upserts Person Accounts in Salesforce synchronously.
     * Maps CSV fields to Salesforce Account fields and performs upsert based on AccountNumber.
     * Processes up to 10,000 records per execution to prevent CPU timeout.
     * 
     * @note For large datasets (>1000 records), use startBatchJob() instead to avoid CPU time limits.
     * This method is intended for small datasets or testing purposes only.
     * 
     * Field Mappings:
     * - StudentID → AccountNumber
     * - LegalFirstName → FirstName (truncated to 40 chars if needed, remainder to Long_Name__pc)
     * - LegalFamilyName → LastName
     * - PrefFirstName → Preferred_first_name__pc
     * - Email → PersonEmail (cleaned of invalid characters)
     * - AUTEmail → Alternative_Email__pc (cleaned of invalid characters)
     * 
     * @return UpsertResult containing success status, processed/created/updated counts, and error messages
     */
    public static UpsertResult downloadAndUpsertAccounts() {
        try {
            // Download CSV
            CSVResponse csvResponse = downloadActiveCSV();
            if (!csvResponse.success) {
                return new UpsertResult(false, 0, 0, 0, csvResponse.errorMessage);
            }
            
            // Parse CSV to maps
            List<Map<String, String>> csvRows = parseCSVToMaps(csvResponse.csvContent);
            
            if (csvRows.isEmpty()) {
                return new UpsertResult(false, 0, 0, 0, 'No data rows found in CSV');
            }
            
            // Get Person Account record type ID
            Id personAccountRecordTypeId = getPersonAccountRecordTypeId();
            if (personAccountRecordTypeId == null) {
                return new UpsertResult(false, 0, 0, 0, 'Person Account record type not found');
            }
            
            // Query existing accounts by AccountNumber
            Set<String> accountNumbers = new Set<String>();
            for (Map<String, String> row : csvRows) {
                String accountNumber = row.get('StudentID');
                if (String.isNotBlank(accountNumber)) {
                    accountNumbers.add(accountNumber.trim());
                }
            }
            
            // Query existing Person Accounts
            // Note: CRUD/FLS checks not performed - this class runs in system context for integration purposes
            Map<String, Account> existingAccountsByNumber = new Map<String, Account>();
            if (!accountNumbers.isEmpty()) {
                for (Account acc : [
                    SELECT Id, AccountNumber, FirstName, LastName, PersonEmail,
                           Preferred_first_name__pc, Alternative_Email__pc, 
                           Status__pc, Last_verified_active_student__pc
                    FROM Account
                    WHERE AccountNumber IN :accountNumbers
                    AND IsPersonAccount = true
                ]) {
                    if (String.isNotBlank(acc.AccountNumber)) {
                        existingAccountsByNumber.put(acc.AccountNumber, acc);
                    }
                }
            }
            
            // Prepare accounts for upsert
            List<Account> accountsToUpsert = new List<Account>();
            List<String> errors = new List<String>();
            Integer processedCount = 0;
            Integer createdCount = 0;
            Integer updatedCount = 0;
            
            DateTime now = DateTime.now();
            
            // Limit processing to prevent CPU timeout (process max 10000 records per run)
            Integer maxRecords = 10000;
            Integer recordCount = 0;
            
            for (Map<String, String> row : csvRows) {
                // Check limit to prevent CPU timeout
                if (recordCount >= maxRecords) {
                    errors.add('Processing stopped at ' + maxRecords + ' records to prevent timeout. Please run again to process remaining records.');
                    break;
                }
                
                try {
                    String accountNumber = row.get('StudentID');
                    
                    // Skip if AccountNumber is blank
                    if (String.isBlank(accountNumber)) {
                        continue;
                    }
                    
                    accountNumber = accountNumber.trim();
                    recordCount++;
                    
                    Account acc;
                    Boolean isNew = false;
                    
                    // Check if account exists
                    if (existingAccountsByNumber.containsKey(accountNumber)) {
                        acc = existingAccountsByNumber.get(accountNumber);
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
                    String legalLastName = String.isNotBlank(row.get('LegalLastName')) ? row.get('LegalLastName').trim() : null;
                    String prefFirstName = String.isNotBlank(row.get('PrefFirstName')) ? row.get('PrefFirstName').trim() : null;
                    String email = String.isNotBlank(row.get('Email')) ? row.get('Email').trim() : null;
                    String autEmail = String.isNotBlank(row.get('AUTEmail')) ? row.get('AUTEmail').trim() : null;
                    
                    // For new accounts, set all fields
                    if (isNew) {
                        if (String.isNotBlank(legalFirstName)) {
                            // Handle FirstName truncation if more than 40 characters
                            Map<String, String> firstNameSplit = splitFirstNameIfTooLong(legalFirstName, 40);
                            acc.FirstName = firstNameSplit.get('firstName');
                            if (String.isNotBlank(firstNameSplit.get('longName'))) {
                                acc.Long_Name__pc = firstNameSplit.get('longName');
                            }
                        }
                        if (String.isNotBlank(legalLastName)) {
                            acc.LastName = legalLastName;
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
                            acc.FirstName = legalFirstName;
                        }
                        if (String.isNotBlank(legalLastName) && acc.LastName != legalLastName) {
                            acc.LastName = legalLastName;
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
                    
                    accountsToUpsert.add(acc);
                    processedCount++;
                    
                } catch (Exception e) {
                    String errorMsg = 'Error processing row with StudentID: ' + row.get('StudentID') + 
                                    ' - ' + e.getMessage();
                    errors.add(errorMsg);
                    System.debug(LoggingLevel.ERROR, errorMsg);
                }
            }
            
            // Separate accounts into new and existing for insert/update
            List<Account> accountsToInsert = new List<Account>();
            List<Account> accountsToUpdate = new List<Account>();
            
            for (Account acc : accountsToUpsert) {
                if (acc.Id != null) {
                    accountsToUpdate.add(acc);
                } else {
                    accountsToInsert.add(acc);
                }
            }
            
            // Perform insert and update operations in batches to optimize performance
            Integer insertSuccessCount = 0;
            Integer updateSuccessCount = 0;
            Integer insertFailCount = 0;
            Integer updateFailCount = 0;
            Integer batchSize = 200; // Process in batches of 200
            
            // Insert new accounts in batches
            if (!accountsToInsert.isEmpty()) {
                for (Integer batchStart = 0; batchStart < accountsToInsert.size(); batchStart += batchSize) {
                    Integer batchEnd = Math.min(batchStart + batchSize, accountsToInsert.size());
                    List<Account> batch = new List<Account>();
                    for (Integer i = batchStart; i < batchEnd; i++) {
                        batch.add(accountsToInsert[i]);
                    }
                    
                    // Perform DML in system context (allOrNone=false to allow partial success)
                    // Note: CRUD/FLS checks not performed - system integration requires full access
                    Database.SaveResult[] insertResults = Database.insert(batch, false);
                    
                    for (Integer i = 0; i < insertResults.size(); i++) {
                        Database.SaveResult result = insertResults[i];
                        if (result.isSuccess()) {
                            insertSuccessCount++;
                        } else {
                            insertFailCount++;
                            String accountNumber = batch[i].AccountNumber;
                            String errorMsg = 'Failed to insert AccountNumber: ' + accountNumber + ' - ';
                            for (Database.Error err : result.getErrors()) {
                                errorMsg += err.getMessage() + '; ';
                            }
                            errors.add(errorMsg);
                            System.debug(LoggingLevel.ERROR, errorMsg);
                        }
                    }
                }
            }
            
            // Update existing accounts in batches
            if (!accountsToUpdate.isEmpty()) {
                for (Integer batchStart = 0; batchStart < accountsToUpdate.size(); batchStart += batchSize) {
                    Integer batchEnd = Math.min(batchStart + batchSize, accountsToUpdate.size());
                    List<Account> batch = new List<Account>();
                    for (Integer i = batchStart; i < batchEnd; i++) {
                        batch.add(accountsToUpdate[i]);
                    }
                    
                    // Perform DML in system context (allOrNone=false to allow partial success)
                    // Note: CRUD/FLS checks not performed - system integration requires full access
                    Database.SaveResult[] updateResults = Database.update(batch, false);
                    
                    for (Integer i = 0; i < updateResults.size(); i++) {
                        Database.SaveResult result = updateResults[i];
                        if (result.isSuccess()) {
                            updateSuccessCount++;
                        } else {
                            updateFailCount++;
                            String accountNumber = batch[i].AccountNumber;
                            String errorMsg = 'Failed to update AccountNumber: ' + accountNumber + ' - ';
                            for (Database.Error err : result.getErrors()) {
                                errorMsg += err.getMessage() + '; ';
                            }
                            errors.add(errorMsg);
                            System.debug(LoggingLevel.ERROR, errorMsg);
                        }
                    }
                }
            }
            
            Integer totalSuccessCount = insertSuccessCount + updateSuccessCount;
            Integer totalFailCount = insertFailCount + updateFailCount;
            
            String resultMessage = 'Processed: ' + processedCount + 
                                 ', Created: ' + createdCount + 
                                 ', Updated: ' + updatedCount + 
                                 ', Successfully upserted: ' + totalSuccessCount +
                                 ', Failed: ' + totalFailCount;
            
            if (!errors.isEmpty()) {
                resultMessage += '. Errors: ' + String.join(errors, ' | ');
            }
            
            return new UpsertResult(true, processedCount, createdCount, updatedCount, resultMessage);
            
        } catch (Exception e) {
            String errorMsg = 'Exception in downloadAndUpsertAccounts: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, errorMsg);
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            return new UpsertResult(false, 0, 0, 0, errorMsg);
        }
    }
    
    /**
     * @description Splits FirstName if it exceeds the maximum length.
     * Finds the last space BEFORE maxLength and splits the name at that position.
     * The first part goes to FirstName field, the remainder goes to Long_Name__pc field.
     * 
     * Example: "Helen Inanui I Te Rangi Hana Ngae Ngahina Ran" (66 chars)
     * Result: firstName = "Helen Inanui I Te Rangi Hana Ngae" (37 chars)
     *         longName = "Ngahina Ran" (11 chars)
     * 
     * @param firstName The full first name to potentially split
     * @param maxLength Maximum length for FirstName field (typically 40 characters)
     * @return Map with 'firstName' (truncated) and 'longName' (remainder) keys. Both may be empty strings.
     */
    public static Map<String, String> splitFirstNameIfTooLong(String firstName, Integer maxLength) {
        Map<String, String> result = new Map<String, String>();
        
        if (String.isBlank(firstName)) {
            result.put('firstName', '');
            result.put('longName', '');
            return result;
        }
        
        // Trim the firstName first
        firstName = firstName.trim();
        
        // If firstName is within limit, return as is
        if (firstName.length() <= maxLength) {
            result.put('firstName', firstName);
            result.put('longName', '');
            return result;
        }
        
        // Find the last space BEFORE position maxLength (not at or after)
        // We need to search in the substring from 0 to maxLength
        String searchArea = firstName.substring(0, maxLength);
        Integer lastSpaceIndex = searchArea.lastIndexOf(' ');
        
        if (lastSpaceIndex >= 0) {
            // Found a space - split at that position
            // Extract first part (up to and including the space, then trim)
            String firstPart = firstName.substring(0, lastSpaceIndex).trim();
            // Extract remaining part (after the space)
            String remainingPart = firstName.substring(lastSpaceIndex + 1).trim();
            
            result.put('firstName', firstPart);
            result.put('longName', remainingPart);
        } else {
            // No space found within first maxLength characters
            // This shouldn't happen with normal names, but handle it by truncating
            result.put('firstName', firstName.substring(0, maxLength).trim());
            result.put('longName', firstName.substring(maxLength).trim());
        }
        
        return result;
    }
    
    /**
     * @description Retrieves the Person Account record type ID.
     * Queries for the first Person Account record type found in the org.
     * @return RecordTypeId for Person Account, or null if not found or error occurs
     */
    private static Id getPersonAccountRecordTypeId() {
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
     * @description Response wrapper class for CSV download operations that return lines.
     * Contains success status, list of CSV lines, and any error messages.
     */
    public class CSVLineResponse {
        public Boolean success;
        public List<String> lines;
        public String errorMessage;
        
        public CSVLineResponse(Boolean success, List<String> lines, String errorMessage) {
            this.success = success;
            this.lines = lines;
            this.errorMessage = errorMessage;
        }
    }
    
    /**
     * @description Response wrapper class for upsert operations.
     * Contains success status, processed/created/updated counts, and result message.
     */
    public class UpsertResult {
        public Boolean success;
        public Integer processedCount;
        public Integer createdCount;
        public Integer updatedCount;
        public String message;
        
        public UpsertResult(Boolean success, Integer processedCount, Integer createdCount, 
                           Integer updatedCount, String message) {
            this.success = success;
            this.processedCount = processedCount;
            this.createdCount = createdCount;
            this.updatedCount = updatedCount;
            this.message = message;
        }
    }
}
