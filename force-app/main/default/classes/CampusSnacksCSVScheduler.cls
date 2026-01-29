/**
 * @description Schedulable class to run Campus Snacks CSV sync on a recurring schedule.
 * Automatically starts the batch job to sync Person Account data from the Campus Snacks API.
 * 
 * @author Salesforce Development Team
 * @date 2024
 * 
 * @note This class runs in system context (without sharing) to ensure scheduled jobs succeed.
 * 
 * To schedule this job:
 * 1. In Salesforce Setup, go to Apex Classes
 * 2. Click "Schedule Apex"
 * 3. Select "CampusSnacksCSVScheduler"
 * 4. Set your preferred schedule (daily, weekly, etc.)
 * 
 * Or use the Developer Console:
 * System.schedule('Campus Snacks CSV Sync', '0 0 2 * * ?', new CampusSnacksCSVScheduler());
 * (This example runs daily at 2 AM)
 */
public without sharing class CampusSnacksCSVScheduler implements Schedulable {
    
    /**
     * @description Execute method called by the Salesforce scheduler.
     * Starts the batch job to sync Campus Snacks CSV data. Handles errors gracefully.
     * @param sc The SchedulableContext provided by the platform
     */
    public void execute(SchedulableContext sc) {
        try {
            // Start the batch job with batch size of 200
            Id jobId = CampusSnacksCSVDownloader.startBatchJob(200);
            System.debug(LoggingLevel.INFO, 'Campus Snacks CSV Sync scheduled job started. Batch Job ID: ' + jobId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error starting Campus Snacks CSV Sync scheduled job: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        }
    }
}
