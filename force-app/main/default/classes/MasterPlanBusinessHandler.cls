public with sharing class MasterPlanBusinessHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'MasterPlanBusinessHandler';

    // MP statuses that trigger child-HP archiving
    private static final Set<String> CLOSED_MP_STATUSES = new Set<String>{
        'Study Closed - Complete',
        'Study Closed - Incomplete'
    };

    // HP statuses considered "still active" that should be closed out with the study
    @TestVisible
    private static final Set<String> ELIGIBLE_HP_STATUSES = new Set<String>{
        'Need to be Screened',
        'Pending Screen (Att 1)',
        'Pending Screen (Att 2)',
        'Pending Screen (Att 3)',
        'PPS - ATT 1',
        'PPS - ATT 2',
        'PPS - ATT 3',
        'Pending Approval',
        'Scheduling (Att 1)',
        'Scheduling (Att 2)',
        'Scheduling (Att 3)',
        'On Hold',
        'Rescheduling',
        'Back-Up Participant',
        'Pending Medical Records_Digital Pull',
        'Pending Medical Records',
        'NTBS-Delayed Outreach',
        'Digital Screen - Pending',
        'Pending DVF',
        'DVF Received',
        'MRs received'
    };

    @TestVisible
    private static final String TARGET_HP_STATUS = 'At Enrollment Capacity';

    public void beforeInsert(List<SObject> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) return;
        try {
            stampCsmFromOpp((List<MasterPlan__c>) newRecords);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}

    public void beforeDelete(Map<Id, SObject> oldMap) {}

    public void afterInsert(List<SObject> newRecords) {}

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        if (newRecords == null || newRecords.isEmpty()) return;
        try {
            findOpportunitiesToUpdate(
                (List<MasterPlan__c>) newRecords,
                (Map<Id, MasterPlan__c>) oldMap
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
        try {
            closeHPsForStudyClosure(
                (List<MasterPlan__c>) newRecords,
                (Map<Id, MasterPlan__c>) oldMap
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterDelete(Map<Id, SObject> oldMap) {
        if (oldMap == null || oldMap.isEmpty()) return;
        try {
            findOpportunitiesToUpdate(
                (List<MasterPlan__c>) oldMap.values(),
                null
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUndelete(List<SObject> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) return;
        try {
            findOpportunitiesToUpdate(
                (List<MasterPlan__c>) newRecords,
                null
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private static void stampCsmFromOpp(List<MasterPlan__c> mps) {
        Set<Id> oppIds = new Set<Id>();
        for (MasterPlan__c mp : mps) {
            if (mp.Opportunity__c != null) {
                oppIds.add(mp.Opportunity__c);
            }
        }
        if (oppIds.isEmpty()) return;

        Map<Id, Id> csmByOppId = new Map<Id, Id>();
        for (Opportunity o : [
            SELECT Id, CSM__c
            FROM Opportunity
            WHERE Id IN :oppIds
            AND CSM__c != null
        ]) {
            csmByOppId.put(o.Id, o.CSM__c);
        }

        for (MasterPlan__c m : mps) {
            if (csmByOppId.containsKey(m.Opportunity__c)) {
                m.CSM__c = csmByOppId.get(m.Opportunity__c);
            }
        }
    }

    private static void findOpportunitiesToUpdate(
        List<MasterPlan__c> newRecords,
        Map<Id, MasterPlan__c> oldRecords
    ) {
        Set<Id> opportunityIds = new Set<Id>();

        for (MasterPlan__c sp : newRecords) {
            if ((oldRecords == null && sp.Opportunity__c != null) ||
                (oldRecords != null && sp.Opportunity__c != oldRecords.get(sp.Id).Opportunity__c)) {

                if (sp.Opportunity__c != null) {
                    opportunityIds.add(sp.Opportunity__c);
                }
                if (oldRecords != null && oldRecords.get(sp.Id).Opportunity__c != null) {
                    opportunityIds.add(oldRecords.get(sp.Id).Opportunity__c);
                }
            }
        }

        if (opportunityIds.isEmpty()) return;

        Map<Id, Decimal> caseCount = new Map<Id, Decimal>();
        for (AggregateResult ag : [
            SELECT COUNT(Id) counter, Master_Plan__r.Opportunity__c opp
            FROM Case
            WHERE Master_Plan__r.Opportunity__c IN :opportunityIds
            GROUP BY Master_Plan__r.Opportunity__c
        ]) {
            caseCount.put((Id) ag.get('opp'), (Decimal) ag.get('counter'));
        }

        Map<Id, Decimal> subjectComp = new Map<Id, Decimal>();
        for (AggregateResult ag : [
            SELECT SUM(Amount_Paid_Number__c) sumAmount, MasterPlan__r.Opportunity__c opp
            FROM PurchaseOrder__c
            WHERE MasterPlan__r.Opportunity__c IN :opportunityIds
              AND Amount_Paid__c != null
              AND Date_of_Payment__c != null
            GROUP BY MasterPlan__r.Opportunity__c
        ]) {
            subjectComp.put((Id) ag.get('opp'), (Decimal) ag.get('sumAmount'));
        }

        Map<Id, Decimal> phlebComp = new Map<Id, Decimal>();
        for (AggregateResult ag : [
            SELECT SUM(Phlebotomist_Compensation__c) sumAmount, MasterPlan__r.Opportunity__c opp
            FROM PurchaseOrder__c
            WHERE MasterPlan__r.Opportunity__c IN :opportunityIds
              AND (Status__c = 'Complete' OR Incomplete_SO_Phleb_Paid__c = true)
            GROUP BY MasterPlan__r.Opportunity__c
        ]) {
            phlebComp.put((Id) ag.get('opp'), (Decimal) ag.get('sumAmount'));
        }

        List<Opportunity> oppList = new List<Opportunity>();
        for (Id i : opportunityIds) {
            Opportunity opp = new Opportunity(Id = i);
            opp.Number_of_cases__c = caseCount.containsKey(i) ? caseCount.get(i) : 0;
            opp.Total_Opp_Subject_Compensation__c = subjectComp.containsKey(i) ? subjectComp.get(i) : 0;
            opp.Total_Opp_Phleb_Compensation__c = phlebComp.containsKey(i) ? phlebComp.get(i) : 0;
            oppList.add(opp);
        }

        if (!oppList.isEmpty()) {
            List<Database.SaveResult> results = Database.update(oppList, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error e : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Opportunity update failed: ' + e.getMessage() + ' | OppId: ' + oppList[i].Id + ' | Fields: ' + e.getFields());
                    }
                }
            }
        }
    }

    // Detects MPs newly transitioning to a closed status and dispatches the HP
    // update asynchronously so it does not block or fail the MP save transaction.
    private static void closeHPsForStudyClosure(
        List<MasterPlan__c> newMps,
        Map<Id, MasterPlan__c> oldMap
    ) {
        Set<Id> closedMpIds = new Set<Id>();
        for (MasterPlan__c mp : newMps) {
            MasterPlan__c oldMp = (oldMap != null) ? oldMap.get(mp.Id) : null;
            Boolean isNowClosed = CLOSED_MP_STATUSES.contains(mp.Status__c);
            Boolean wasClosed   = oldMp != null && CLOSED_MP_STATUSES.contains(oldMp.Status__c);
            if (isNowClosed && !wasClosed) {
                closedMpIds.add(mp.Id);
            }
        }
        if (closedMpIds.isEmpty()) return;

        // Dispatch asynchronously; fall back to sync only when already inside a
        // future or batch context where @future calls are not permitted.
        if (!System.isFuture() && !System.isBatch()) {
            archiveEligibleHPsAsync(closedMpIds);
        } else {
            archiveEligibleHPs(closedMpIds);
        }
    }

    // Async entry point — queued after the MP transaction commits.
    @future
    private static void archiveEligibleHPsAsync(Set<Id> mpIds) {
        archiveEligibleHPs(mpIds);
    }

    // Sets eligible HP statuses to At Enrollment Capacity for the given MP IDs.
    private static void archiveEligibleHPs(Set<Id> mpIds) {
        List<HealthProfile__c> toUpdate = new List<HealthProfile__c>();
        for (HealthProfile__c hp : [
            SELECT Id
            FROM HealthProfile__c
            WHERE Master_Plan__c IN :mpIds
              AND Status__c IN :ELIGIBLE_HP_STATUSES
        ]) {
            toUpdate.add(new HealthProfile__c(Id = hp.Id, Status__c = TARGET_HP_STATUS));
        }
        if (toUpdate.isEmpty()) return;

        Database.SaveResult[] results = Database.update(toUpdate, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'HP status update failed: ' + err.getStatusCode() + ': ' + err.getMessage() + ' | HPId=' + toUpdate[i].Id);
                }
            }
        }
    }
}
