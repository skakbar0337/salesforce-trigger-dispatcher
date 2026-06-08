trigger ClinicalEntryQCTrigger on ClinicalEntry__c (after insert, after update) {

    Set<Id> projectPlanIds = new Set<Id>();

    // Gather the Master Plan IDs from the incoming records that meet the criteria
    for (ClinicalEntry__c  po : Trigger.new) {
        if (po.Project_Plan__c != null) {
            projectPlanIds.add(po.Project_Plan__c);
        }
    }

    // Query the related Master Plan object to check the Study_Type__c and Aphaeresis_Collection_Type__c
    Map<Id, ProjectPlan__c> projectPlanMap = new Map<Id, ProjectPlan__c>([
        SELECT Id, Study_Type__c, Aphaeresis_Collection_Type__c
        FROM ProjectPlan__c
        WHERE Id IN :projectPlanIds
    ]);

    // Loop through each HP in the trigger
    for (ClinicalEntry__c  newPO : Trigger.new) {
        ProjectPlan__c projectPlan = projectPlanMap.get(newPO.Project_Plan__c);

        // Check if the related Master Plan's Study_Type__c and Aphaeresis_Collection_Type__c meet the criteria
        if (projectPlan != null && 
            projectPlan.Study_Type__c == 'GMP Aphaeresis' && 
            projectPlan.Aphaeresis_Collection_Type__c == 'Collection' && newPO.Patient__c != null) {

            // Query for the most recent 'Completed' HP where Patient ID matches and the Screening criteria is met
            for (ClinicalEntry__c  so : [SELECT Id, CreatedDate, Appointment_Date_Time__c
                                                        FROM ClinicalEntry__c
                                                        WHERE (Status__c = 'Donated Blood'
                                                        OR Status__c = 'Appointment Scheduled (Screening)')
                                                        AND Patient__c = :newPO.Patient__c
                                                        AND Project_Plan__r.Study_Type__c = 'GMP Aphaeresis'
                                                        AND Project_Plan__r.Aphaeresis_Collection_Type__c = 'Screening'
                                                        ORDER BY Appointment_Date_Time__c DESC
                                               LIMIT 1]) 
            {
            // Check if a Screening HP is older than 7 days from Collection SO Appt Date
            if (so != null && so.Appointment_Date_Time__c != null && newPO.Appointment_Date_Time__c != null) {
                Integer daysDifference = so.Appointment_Date_Time__c.Date().daysBetween(newPO.Appointment_Date_Time__c.Date());

                if (daysDifference > 7) {
                    newPO.addError('You cannot create or update this GMP Collection SO because the related GMP Screening SO was completed more than 7 days ago.');
                }
            }                
                                                   
            }

        }
    }
}