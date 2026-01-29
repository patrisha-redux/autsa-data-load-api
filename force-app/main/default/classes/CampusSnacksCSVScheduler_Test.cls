/**
 * @description Test class for CampusSnacksCSVScheduler
 * Tests scheduled job execution and batch job initiation
 */
@IsTest
private class CampusSnacksCSVScheduler_Test {
    
    /**
     * @description Mock HTTP response for successful CSV download
     */
    private class CSVSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/csv');
            res.setStatusCode(200);
            String csvContent = 'StudentID,LegalFirstName,LegalFamilyName,PrefFirstName,Email,AUTEmail\n' +
                               '123456,John,Doe,Johnny,john.doe@example.com,john.doe@aut.ac.nz';
            res.setBody(csvContent);
            return res;
        }
    }
    
    /**
     * @description Setup test data including custom setting
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
    }
    
    /**
     * @description Test scheduler execution
     */
    @IsTest
    static void testSchedulerExecution() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        CampusSnacksCSVScheduler scheduler = new CampusSnacksCSVScheduler();
        String cronExpression = '0 0 2 * * ?'; // Daily at 2 AM
        String jobName = 'Test Campus Snacks CSV Sync';
        
        // Schedule the job
        Id scheduleId = System.schedule(jobName, cronExpression, scheduler);
        Test.stopTest();
        
        // Verify scheduled job was created
        CronTrigger scheduledJob = [
            SELECT Id, CronJobDetail.Name, State, NextFireTime
            FROM CronTrigger 
            WHERE Id = :scheduleId
        ];
        
        System.assertNotEquals(null, scheduledJob, 'Scheduled job should exist');
        System.assertEquals(jobName, scheduledJob.CronJobDetail.Name, 'Job name should match');
        
        // Verify batch job was started (check AsyncApexJob)
        List<AsyncApexJob> batchJobs = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        System.assert(batchJobs.size() > 0, 'Batch job should be started by scheduler');
    }
    
    /**
     * @description Test scheduler execution with error handling
     */
    @IsTest
    static void testSchedulerExecution_WithError() {
        // Delete custom setting to cause error
        delete [SELECT Id FROM CampusSnackAPI__c LIMIT 1];
        
        Test.startTest();
        CampusSnacksCSVScheduler scheduler = new CampusSnacksCSVScheduler();
        String cronExpression = '0 0 2 * * ?';
        String jobName = 'Test Campus Snacks CSV Sync Error';
        
        // Scheduler should handle error gracefully - execute method catches exceptions
        Id scheduleId = System.schedule(jobName, cronExpression, scheduler);
        Test.stopTest();
        
        // Scheduler should complete without throwing exception (error is logged, not thrown)
        System.assertNotEquals(null, scheduleId, 'Scheduled job should be created even if batch fails');
        
        // Verify scheduled job was created
        CronTrigger scheduledJob = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger 
            WHERE Id = :scheduleId
        ];
        System.assertNotEquals(null, scheduledJob, 'Scheduled job should exist');
    }
    
    /**
     * @description Test scheduler can be scheduled multiple times
     */
    @IsTest
    static void testSchedulerMultipleSchedules() {
        Test.setMock(HttpCalloutMock.class, new CSVSuccessMock());
        
        Test.startTest();
        CampusSnacksCSVScheduler scheduler = new CampusSnacksCSVScheduler();
        String cronExpression = '0 0 2 * * ?';
        
        // Schedule multiple jobs
        Id scheduleId1 = System.schedule('Test Sync 1', cronExpression, scheduler);
        Id scheduleId2 = System.schedule('Test Sync 2', cronExpression, scheduler);
        Test.stopTest();
        
        // Verify both scheduled jobs exist
        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger 
            WHERE Id IN (:scheduleId1, :scheduleId2)
        ];
        
        System.assertEquals(2, scheduledJobs.size(), 'Both scheduled jobs should exist');
    }
}
