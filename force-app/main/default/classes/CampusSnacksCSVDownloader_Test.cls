/**
 * @description Test class for CampusSnacksCSVDownloader
 * Tests CSV download, parsing, field mapping, and upsert operations
 */
@IsTest
private class CampusSnacksCSVDownloader_Test {
    
    /**
     * @description Mock HTTP response for successful CSV download
     */
    private class CSVSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/csv');
            res.setStatusCode(200);
            
            // Sample CSV content
            String csvContent = 'StudentID,LegalFirstName,LegalFamilyName,PrefFirstName,Email,AUTEmail\n' +
                               '123456,John,Doe,Johnny,john.doe@example.com,john.doe@aut.ac.nz\n' +
                               '789012,Jane,Smith,Jane,jane.smith@example.com,jane.smith@aut.ac.nz\n' +
                               '345678,"Helen Inanui I Te Rangi Hana Ngae Ngahina Ran",Brown,Helen,helen.brown@example.com,helen.brown@aut.ac.nz';
            res.setBody(csvContent);
            return res;
        }
    }
    
    /**
     * @description Mock HTTP response for failed CSV download
     */
    private class CSVErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(401);
            res.setStatus('Unauthorized');
            res.setBody('Invalid token');
            return res;
        }
    }
    
    /**
     * @description Mock HTTP response for server error
     */
    private class CSVServerErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('Server error');
            return res;
        }
    }
    
    /**
     * @description Setup test data including custom setting and Person Account record type
     */
    @TestSetup
    static void setupTestData() {
        // Create CampusSnackAPI custom setting
        CampusSnackAPI__c apiSettings = new CampusSnackAPI__c(
            Name = 'Default',
            Endpoint__c = 'https://campus-snacks-production.up.railway.app/api/download/active.csv',
            Token__c = 'test-token-12345'
        );
        insert apiSettings;
        
        // Create existing Person Account for testing updates
        Id personAccountRTId = getPersonAccountRecordTypeId();
        if (personAccountRTId != null) {
            Account existingAccount = new Account(
                RecordTypeId = personAccountRTId,
                AccountNumber = '123456',
                FirstName = 'Existing',
                LastName = 'Account',
                PersonEmail = 'existing@example.com',
                Status__pc = 'Inactive'
            );
            insert existingAccount;
        }
    }
    
    /**
     * @description Helper method to get Person Account record type ID
     */
    private static Id getPersonAccountRecordTypeId() {
        try {
            RecordType personAccountRT = [
                SELECT Id FROM RecordType 
                WHERE SobjectType = 'Account' 
                AND IsPersonType = true 
                LIMIT 1
            ];
            return personAccountRT.Id;
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Test successful CSV download
     */
    @IsTest
    static void testDownloadActiveCSV_Success() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        CampusSnacksCSVDownloader.CSVResponse response = CampusSnacksCSVDownloader.downloadActiveCSV();
        Test.stopTest();
        
        System.assert(response.success, 'CSV download should succeed');
        System.assertNotEquals(null, response.csvContent, 'CSV content should not be null');
        System.assert(response.csvContent.contains('StudentID'), 'CSV should contain headers');
        System.assertEquals(null, response.errorMessage, 'Error message should be null on success');
    }
    
    /**
     * @description Test CSV download with authentication error
     */
    @IsTest
    static void testDownloadActiveCSV_AuthenticationError() {
        Test.setMock(HttpCalloutMock.class, new CSVErrorMock());
        
        Test.startTest();
        CampusSnacksCSVDownloader.CSVResponse response = CampusSnacksCSVDownloader.downloadActiveCSV();
        Test.stopTest();
        
        System.assert(!response.success, 'CSV download should fail');
        System.assertEquals(null, response.csvContent, 'CSV content should be null on error');
        System.assertNotEquals(null, response.errorMessage, 'Error message should not be null');
        System.assert(response.errorMessage.contains('401') || response.errorMessage.contains('Unauthorized'), 
                     'Error message should contain error details');
    }
    
    /**
     * @description Test CSV download with server error
     */
    @IsTest
    static void testDownloadActiveCSV_ServerError() {
        Test.setMock(HttpCalloutMock.class, new CSVServerErrorMock());
        
        Test.startTest();
        CampusSnacksCSVDownloader.CSVResponse response = CampusSnacksCSVDownloader.downloadActiveCSV();
        Test.stopTest();
        
        System.assert(!response.success, 'CSV download should fail');
        System.assertEquals(null, response.csvContent, 'CSV content should be null on error');
        System.assertNotEquals(null, response.errorMessage, 'Error message should not be null');
    }
    
    /**
     * @description Test CSV download when custom setting is not configured
     */
    @IsTest
    static void testDownloadActiveCSV_MissingCustomSetting() {
        // Delete custom setting
        delete [SELECT Id FROM CampusSnackAPI__c LIMIT 1];
        
        Test.startTest();
        CampusSnacksCSVDownloader.CSVResponse response = CampusSnacksCSVDownloader.downloadActiveCSV();
        Test.stopTest();
        
        System.assert(!response.success, 'CSV download should fail when custom setting is missing');
        System.assertEquals(null, response.csvContent, 'CSV content should be null');
        System.assert(response.errorMessage.contains('CampusSnackAPI custom setting not configured'), 
                     'Error message should indicate missing custom setting');
    }
    
    /**
     * @description Test downloading CSV as lines
     */
    @IsTest
    static void testDownloadActiveCSVAsLines_Success() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        CampusSnacksCSVDownloader.CSVLineResponse response = CampusSnacksCSVDownloader.downloadActiveCSVAsLines();
        Test.stopTest();
        
        System.assert(response.success, 'CSV download should succeed');
        System.assertNotEquals(null, response.lines, 'Lines should not be null');
        System.assert(response.lines.size() > 0, 'Should have at least one line');
        System.assertEquals(null, response.errorMessage, 'Error message should be null on success');
    }
    
    /**
     * @description Test parsing CSV to maps
     */
    @IsTest
    static void testParseCSVToMaps() {
        String csvContent = 'StudentID,LegalFirstName,LegalFamilyName,Email\n' +
                           '123456,John,Doe,john.doe@example.com\n' +
                           '789012,Jane,Smith,jane.smith@example.com';
        
        Test.startTest();
        List<Map<String, String>> result = CampusSnacksCSVDownloader.parseCSVToMaps(csvContent);
        Test.stopTest();
        
        System.assertEquals(2, result.size(), 'Should parse 2 data rows');
        System.assertEquals('123456', result[0].get('StudentID'), 'First row StudentID should match');
        System.assertEquals('John', result[0].get('LegalFirstName'), 'First row LegalFirstName should match');
        System.assertEquals('Doe', result[0].get('LegalFamilyName'), 'First row LegalFamilyName should match');
        System.assertEquals('789012', result[1].get('StudentID'), 'Second row StudentID should match');
    }
    
    /**
     * @description Test parsing CSV with quoted fields
     */
    @IsTest
    static void testParseCSVToMaps_WithQuotedFields() {
        String csvContent = 'StudentID,LegalFirstName,LegalFamilyName\n' +
                           '123456,"John, Jr",Doe\n' +
                           '789012,Jane,"Smith, PhD"';
        
        Test.startTest();
        List<Map<String, String>> result = CampusSnacksCSVDownloader.parseCSVToMaps(csvContent);
        Test.stopTest();
        
        System.assertEquals(2, result.size(), 'Should parse 2 data rows');
        System.assertEquals('John, Jr', result[0].get('LegalFirstName'), 'Should handle quoted fields with commas');
        System.assertEquals('Smith, PhD', result[1].get('LegalFamilyName'), 'Should handle quoted fields with commas');
    }
    
    /**
     * @description Test splitting string into lines
     */
    @IsTest
    static void testSplitIntoLines() {
        String content = 'Line 1\nLine 2\nLine 3';
        
        Test.startTest();
        List<String> lines = CampusSnacksCSVDownloader.splitIntoLines(content);
        Test.stopTest();
        
        System.assertEquals(3, lines.size(), 'Should split into 3 lines');
        System.assertEquals('Line 1', lines[0], 'First line should match');
        System.assertEquals('Line 2', lines[1], 'Second line should match');
        System.assertEquals('Line 3', lines[2], 'Third line should match');
    }
    
    /**
     * @description Test splitting string with Windows line endings
     */
    @IsTest
    static void testSplitIntoLines_WindowsLineEndings() {
        String content = 'Line 1\r\nLine 2\r\nLine 3';
        
        Test.startTest();
        List<String> lines = CampusSnacksCSVDownloader.splitIntoLines(content);
        Test.stopTest();
        
        System.assertEquals(3, lines.size(), 'Should split into 3 lines');
        System.assertEquals('Line 1', lines[0], 'First line should match');
    }
    
    /**
     * @description Test parsing CSV line
     */
    @IsTest
    static void testParseCSVLine() {
        String line = 'StudentID,LegalFirstName,LegalFamilyName,Email';
        
        Test.startTest();
        List<String> fields = CampusSnacksCSVDownloader.parseCSVLine(line);
        Test.stopTest();
        
        System.assertEquals(4, fields.size(), 'Should parse 4 fields');
        System.assertEquals('StudentID', fields[0], 'First field should match');
        System.assertEquals('LegalFirstName', fields[1], 'Second field should match');
    }
    
    /**
     * @description Test splitting FirstName if too long
     */
    @IsTest
    static void testSplitFirstNameIfTooLong() {
        String longName = 'Helen Inanui I Te Rangi Hana Ngae Ngahina Ran'; // 66 characters
        
        Test.startTest();
        Map<String, String> result = CampusSnacksCSVDownloader.splitFirstNameIfTooLong(longName, 40);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.get('firstName'), 'firstName should not be null');
        System.assert(result.get('firstName').length() <= 40, 'firstName should be <= 40 characters');
        System.assertNotEquals(null, result.get('longName'), 'longName should not be null');
        System.assert(result.get('longName').length() > 0, 'longName should have content');
    }
    
    /**
     * @description Test splitting FirstName when it fits within limit
     */
    @IsTest
    static void testSplitFirstNameIfTooLong_WithinLimit() {
        String shortName = 'John'; // 4 characters
        
        Test.startTest();
        Map<String, String> result = CampusSnacksCSVDownloader.splitFirstNameIfTooLong(shortName, 40);
        Test.stopTest();
        
        System.assertEquals(shortName, result.get('firstName'), 'firstName should be unchanged');
        System.assertEquals('', result.get('longName'), 'longName should be empty');
    }
    
    /**
     * @description Test splitting FirstName with no spaces
     */
    @IsTest
    static void testSplitFirstNameIfTooLong_NoSpaces() {
        String longName = 'ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ'; // 52 characters, no spaces
        
        Test.startTest();
        Map<String, String> result = CampusSnacksCSVDownloader.splitFirstNameIfTooLong(longName, 40);
        Test.stopTest();
        
        System.assert(result.get('firstName').length() == 40, 'firstName should be exactly 40 characters');
        System.assert(result.get('longName').length() > 0, 'longName should have remaining characters');
    }
    
    /**
     * @description Test starting batch job
     */
    @IsTest
    static void testStartBatchJob() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        Id jobId = CampusSnacksCSVDownloader.startBatchJob(200);
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Batch job ID should not be null');
        
        // Verify job was created
        AsyncApexJob job = [SELECT Id, Status, JobType FROM AsyncApexJob WHERE Id = :jobId];
        System.assertNotEquals(null, job, 'Batch job should exist');
        System.assertEquals('BatchApex', job.JobType, 'Job type should be BatchApex');
    }
    
    /**
     * @description Test starting batch job with default batch size
     */
    @IsTest
    static void testStartBatchJob_DefaultBatchSize() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        Id jobId = CampusSnacksCSVDownloader.startBatchJob(null);
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Batch job ID should not be null');
    }
    
    /**
     * @description Test downloadAndUpsertAccounts with small dataset
     */
    @IsTest
    static void testDownloadAndUpsertAccounts_Success() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        CampusSnacksCSVDownloader.UpsertResult result = CampusSnacksCSVDownloader.downloadAndUpsertAccounts();
        Test.stopTest();
        
        System.assert(result.success, 'Upsert should succeed');
        System.assert(result.processedCount > 0, 'Should process some records');
        System.assert(result.createdCount >= 0, 'Created count should be non-negative');
        System.assert(result.updatedCount >= 0, 'Updated count should be non-negative');
        
        // Verify accounts were created/updated
        List<Account> accounts = [
            SELECT Id, AccountNumber, FirstName, LastName, PersonEmail, Status__pc 
            FROM Account 
            WHERE AccountNumber IN ('123456', '789012', '345678')
            AND IsPersonAccount = true
        ];
        System.assert(accounts.size() > 0, 'Accounts should be created or updated');
    }
    
    /**
     * @description Test downloadAndUpsertAccounts when CSV download fails
     */
    @IsTest
    static void testDownloadAndUpsertAccounts_DownloadFails() {
        Test.setMock(HttpCalloutMock.class, new CSVErrorMock());
        
        Test.startTest();
        CampusSnacksCSVDownloader.UpsertResult result = CampusSnacksCSVDownloader.downloadAndUpsertAccounts();
        Test.stopTest();
        
        System.assert(!result.success, 'Upsert should fail when download fails');
        System.assertEquals(0, result.processedCount, 'No records should be processed');
        System.assertNotEquals(null, result.message, 'Error message should be present');
    }
}
