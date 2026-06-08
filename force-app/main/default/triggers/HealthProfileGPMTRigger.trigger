trigger HealthProfileGPMTRigger on HealthProfile__c (after insert, after update) {

    Set<Id> masterPlanIds = new Set<Id>();

    // Gather the Master Plan IDs from the incoming records that meet the criteria
    for (HealthProfile__c  po : Trigger.new) {
        if (po.Master_Plan__c != null) {
            masterPlanIds.add(po.Master_Plan__c);
        }
    }

    // Query the related Master Plan object to check the Study_Type__c and Aphaeresis_Collection_Type__c
    Map<Id, MasterPlan__c> masterPlanMap = new Map<Id, MasterPlan__c>([
        SELECT Id, Study_Type__c, Aphaeresis_Collection_Type__c
        FROM MasterPlan__c
        WHERE Id IN :masterPlanIds
    ]);

    // Loop through each HP in the trigger
    for (HealthProfile__c  newPO : Trigger.new) {
        MasterPlan__c masterPlan = masterPlanMap.get(newPO.Master_Plan__c);

        // Check if the related Master Plan's Study_Type__c and Aphaeresis_Collection_Type__c meet the criteria
        if (masterPlan != null && 
            masterPlan.Study_Type__c == 'GMP Aphaeresis' && 
            masterPlan.Aphaeresis_Collection_Type__c == 'Collection' && newPO.Patient__c != null) {

            // Query for the most recent 'Completed' HP where Patient ID matches and the Screening criteria is met
            for (HealthProfile__c  so : [SELECT Id, CreatedDate, Appointment_Date_Time__c
                                                        FROM HealthProfile__c
                                                        WHERE (Status__c = 'Donated Blood'
                                                        OR Status__c = 'Appointment Scheduled (Screening)')
                                                        AND Patient__c = :newPO.Patient__c
                                                        AND Master_Plan__r.Study_Type__c = 'GMP Aphaeresis'
                                                        AND Master_Plan__r.Aphaeresis_Collection_Type__c = 'Screening'
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