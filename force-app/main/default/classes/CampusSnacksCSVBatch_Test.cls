/**
 * @description Test class for CampusSnacksCSVBatch
 * Tests batch processing of CSV data and Person Account upserts
 */
@IsTest
private class CampusSnacksCSVBatch_Test {
    
    /**
     * @description Mock HTTP response for successful CSV download
     */
    private class CSVSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/csv');
            res.setStatusCode(200);
            
            // Sample CSV content with multiple rows
            String csvContent = 'StudentID,LegalFirstName,LegalFamilyName,PrefFirstName,Email,AUTEmail\n' +
                               '123456,John,Doe,Johnny,john.doe@example.com,john.doe@aut.ac.nz\n' +
                               '789012,Jane,Smith,Jane,jane.smith@example.com,jane.smith@aut.ac.nz\n' +
                               '345678,Helen,Brown,Helen,helen.brown@example.com,helen.brown@aut.ac.nz\n' +
                               '111222,Test,User,Test,test.user@example.com,test.user@aut.ac.nz\n' +
                               '333444,Another,Person,Another,another.person@example.com,another.person@aut.ac.nz';
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
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('Server error');
            return res;
        }
    }
    
    /**
     * @description Setup test data including custom setting and existing Person Accounts
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
                Status__pc = 'Inactive',
                Last_verified_active_student__pc = DateTime.now().addDays(-30)
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
     * @description Test batch job execution with successful CSV download
     */
    @IsTest
    static void testBatchExecution_Success() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        // Use batch size equal to or larger than number of records to ensure single execute call in test context
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify job completed
        AsyncApexJob job = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed 
                           FROM AsyncApexJob 
                           WHERE Id = :jobId];
        System.assertNotEquals(null, job, 'Batch job should exist');
        System.assertEquals('Completed', job.Status, 'Batch job should complete successfully');
        
        // Verify accounts were created/updated
        List<Account> accounts = [
            SELECT Id, AccountNumber, FirstName, LastName, PersonEmail, Status__pc, 
                   Last_verified_active_student__pc
            FROM Account 
            WHERE AccountNumber IN ('123456', '789012', '345678', '111222', '333444')
            AND IsPersonAccount = true
        ];
        System.assert(accounts.size() > 0, 'Accounts should be created or updated');
        
        // Verify sync log was created
        List<SObject> syncLogs = [
            SELECT Id, Total_processed_records__c, Total_inserted_records__c, 
                   Total_updated_records__c
            FROM Data_Load_Sync_Logs__c
        ];
        System.assert(syncLogs.size() > 0, 'Sync log should be created');
    }
    
    /**
     * @description Test batch job when CSV download fails
     */
    @IsTest
    static void testBatchExecution_CSVDownloadFails() {
        Test.setMock(HttpCalloutMock.class, new CSVErrorMock());
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        
        try {
            Id jobId = Database.executeBatch(batch, 10);
            Test.stopTest();
            
            // Job should fail in start method
            AsyncApexJob job = [SELECT Id, Status, NumberOfErrors 
                               FROM AsyncApexJob 
                               WHERE Id = :jobId];
            System.assertEquals('Failed', job.Status, 'Batch job should fail');
        } catch (CampusSnacksCSVBatch.BatchException e) {
            Test.stopTest();
            System.assert(e.getMessage().contains('Failed to download CSV'), 
                         'Exception should mention CSV download failure');
        } catch (Exception e) {
            Test.stopTest();
            // In test context, exception may be thrown directly
            System.assert(e.getMessage().contains('Failed to download CSV') || 
                         e.getMessage().contains('CSV'), 
                         'Exception should mention CSV download failure');
        }
    }
    
    /**
     * @description Test batch job with existing accounts (updates)
     */
    @IsTest
    static void testBatchExecution_UpdateExistingAccounts() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        // Verify existing account before batch
        Account existingAccount = [
            SELECT Id, FirstName, LastName, Status__pc, Last_verified_active_student__pc
            FROM Account 
            WHERE AccountNumber = '123456' 
            AND IsPersonAccount = true
            LIMIT 1
        ];
        DateTime oldVerificationDate = existingAccount.Last_verified_active_student__pc;
        String oldFirstName = existingAccount.FirstName;
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        // Use batch size equal to or larger than number of records to ensure single execute call in test context
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify account was updated
        Account updatedAccount = [
            SELECT Id, FirstName, LastName, Status__pc, Last_verified_active_student__pc
            FROM Account 
            WHERE AccountNumber = '123456' 
            AND IsPersonAccount = true
            LIMIT 1
        ];
        
        System.assertEquals('Active', updatedAccount.Status__pc, 'Status should be updated to Active');
        System.assert(updatedAccount.Last_verified_active_student__pc > oldVerificationDate, 
                     'Last verified date should be updated');
        System.assertEquals('John', updatedAccount.FirstName, 'FirstName should be updated from CSV');
    }
    
    /**
     * @description Test batch job with new accounts (inserts)
     */
    @IsTest
    static void testBatchExecution_CreateNewAccounts() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        // Verify account doesn't exist before batch
        List<Account> existingAccounts = [
            SELECT Id FROM Account 
            WHERE AccountNumber = '789012' 
            AND IsPersonAccount = true
        ];
        System.assertEquals(0, existingAccounts.size(), 'Account should not exist before batch');
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        // Use batch size equal to or larger than number of records to ensure single execute call in test context
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify account was created
        List<Account> newAccounts = [
            SELECT Id, AccountNumber, FirstName, LastName, PersonEmail, Status__pc
            FROM Account 
            WHERE AccountNumber = '789012' 
            AND IsPersonAccount = true
        ];
        System.assertEquals(1, newAccounts.size(), 'Account should be created');
        System.assertEquals('Jane', newAccounts[0].FirstName, 'FirstName should match CSV');
        System.assertEquals('Smith', newAccounts[0].LastName, 'LastName should match CSV');
        System.assertEquals('Active', newAccounts[0].Status__pc, 'Status should be Active');
    }
    
    /**
     * @description Mock HTTP response with long FirstName for truncation testing
     */
    private class CSVLongFirstNameMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/csv');
            res.setStatusCode(200);
            String csvContent = 'StudentID,LegalFirstName,LegalFamilyName,PrefFirstName,Email,AUTEmail\n' +
                               '999999,"Helen Inanui I Te Rangi Hana Ngae Ngahina Ran",Brown,Helen,helen@example.com,helen@aut.ac.nz';
            res.setBody(csvContent);
            return res;
        }
    }
    
    /**
     * @description Mock HTTP response with blank StudentID
     */
    private class CSVBlankStudentIDMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/csv');
            res.setStatusCode(200);
            String csvContent = 'StudentID,LegalFirstName,LegalFamilyName,PrefFirstName,Email,AUTEmail\n' +
                               ',John,Doe,Johnny,john.doe@example.com,john.doe@aut.ac.nz\n' +
                               '789012,Jane,Smith,Jane,jane.smith@example.com,jane.smith@aut.ac.nz';
            res.setBody(csvContent);
            return res;
        }
    }
    
    /**
     * @description Mock HTTP response with email containing invalid characters
     */
    private class CSVEmailCleaningMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/csv');
            res.setStatusCode(200);
            String csvContent = 'StudentID,LegalFirstName,LegalFamilyName,PrefFirstName,Email,AUTEmail\n' +
                               '888888,Test,User,Test,test.user@gmail.com,test.user@aut.ac.nz';
            res.setBody(csvContent);
            return res;
        }
    }
    
    /**
     * @description Test batch job with FirstName truncation
     */
    @IsTest
    static void testBatchExecution_FirstNameTruncation() {
        Test.setMock(HttpCalloutMock.class, new CSVLongFirstNameMock());
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        // Use batch size equal to or larger than number of records to ensure single execute call in test context
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify account was created with truncated FirstName
        Account account = [
            SELECT Id, FirstName, Long_Name__pc
            FROM Account 
            WHERE AccountNumber = '999999' 
            AND IsPersonAccount = true
            LIMIT 1
        ];
        
        System.assert(account.FirstName.length() <= 40, 'FirstName should be <= 40 characters');
        System.assertNotEquals(null, account.Long_Name__pc, 'Long_Name__pc should contain remainder');
        System.assert(account.Long_Name__pc.length() > 0, 'Long_Name__pc should not be empty');
    }
    
    /**
     * @description Test batch job with blank StudentID (should be skipped)
     */
    @IsTest
    static void testBatchExecution_BlankStudentID() {
        Test.setMock(HttpCalloutMock.class, new CSVBlankStudentIDMock());
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        // Use batch size equal to or larger than number of records to ensure single execute call in test context
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify only one account was created (row with blank StudentID should be skipped)
        List<Account> accounts = [
            SELECT Id FROM Account 
            WHERE AccountNumber = '789012' 
            AND IsPersonAccount = true
        ];
        System.assertEquals(1, accounts.size(), 'Only account with valid StudentID should be created');
    }
    
    /**
     * @description Test batch job with email cleaning
     */
    @IsTest
    static void testBatchExecution_EmailCleaning() {
        Test.setMock(HttpCalloutMock.class, new CSVEmailCleaningMock());
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        // Use batch size equal to or larger than number of records to ensure single execute call in test context
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify account was created with cleaned email
        Account account = [
            SELECT Id, PersonEmail
            FROM Account 
            WHERE AccountNumber = '888888' 
            AND IsPersonAccount = true
            LIMIT 1
        ];
        
        System.assertNotEquals(null, account.PersonEmail, 'Email should be set');
        // Email cleaning removes non-ASCII and control characters - verify email is valid format
        System.assert(account.PersonEmail.contains('@'), 'Email should contain @ symbol');
        System.assert(account.PersonEmail.contains('.'), 'Email should contain . symbol');
    }
    
    /**
     * @description Test batch job finish method creates sync log
     */
    @IsTest
    static void testBatchExecution_CreatesSyncLog() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        CampusSnacksCSVBatch batch = new CampusSnacksCSVBatch();
        // Use batch size equal to or larger than number of records to ensure single execute call in test context
        Id jobId = Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify sync log was created
        List<SObject> syncLogs = [
            SELECT Id, Total_processed_records__c, Total_inserted_records__c, 
                   Total_updated_records__c, Total_unprocessed_records__c
            FROM Data_Load_Sync_Logs__c
        ];
        
        System.assert(syncLogs.size() > 0, 'Sync log should be created');
        SObject syncLog = syncLogs[0];
        System.assertNotEquals(null, syncLog.get('Total_processed_records__c'), 
                              'Total processed records should be set');
    }
}
