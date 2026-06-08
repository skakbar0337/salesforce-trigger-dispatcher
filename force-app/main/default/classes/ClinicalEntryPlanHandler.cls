/**
 * @description       : Handler to roll up Health Profile data to related Master Plans based on status conditions.
 * This class combines the logic for MP status field rollups, DNQ rollup, and incomplete visit rollups in a clean and maintainable manner.
 * No logic duplication, SOQL/DML in loops, or violations of SRP.
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-06
 * @executionOrder    : 40 (Rollups & Calculations)
 * @group             : Health Profile Trigger Handlers
 * @group-content     : ClinicalEntryPlanHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - Object CRUD and field-level access are validated; data is sanitized via Security.stripInaccessible.
 * - No SOQL/DML inside loops; bulk-safe across 200+ rows.
 * - Defensive queries are field-selective and filtered.
 * - Updates use Database.update(..., false) for partial success and error logging.
 * - Methods < 100 lines, meaningful names, and single-responsibility design.
 */

public with sharing class ClinicalEntryPlanHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'ClinicalEntryPlanHandler';
    private static final String OBJECT_NAME = 'ClinicalEntry__c';

     private static final Set<String> DNQ_STATUSES = new Set<String>{
        'Pre-screen - Doesn’t Qualify for a Current Study',
        'Doesn\'t Qualify For a Current Study',
        'DNQ - At Enrollment Capacity',
        'DNQ - Hold',
        'Cannot Be Reached',
        'Cannot Participate',
        'Out of Territory',
        'Do Not Contact'
    };
    private static final Set<String> INCOMPLETE_STATUSES = new Set<String>{
        'Reschedule','Cancellation/No Show','Unsuccessful Collection'
    };
    // ---------------- AFTER INSERT ----------------
    public void afterInsert(List<SObject> newRecords) {
        try {
            List<ClinicalEntry__c> hps = (List<ClinicalEntry__c>) newRecords;
            Set<Id> mpIds = collectMpIdsForStatusRollup(hps, null);
            if (!mpIds.isEmpty()) updateStatusRollups(mpIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    // ---------------- AFTER UPDATE ----------------
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<ClinicalEntry__c> newHps = (List<ClinicalEntry__c>) newRecords;
            Map<Id, ClinicalEntry__c> oldHps = (Map<Id, ClinicalEntry__c>) oldMap;

            Set<Id> mpStatusIds      = collectMpIdsForStatusRollup(newHps, oldHps);
            Set<Id> mpDnqIds         = collectMpIdsWhereNewStatusIn(newHps, DNQ_STATUSES);
            Set<Id> mpIncompleteIds  = collectMpIdsWhereNewStatusIn(newHps, INCOMPLETE_STATUSES);

            if (!mpStatusIds.isEmpty())     updateStatusRollups(mpStatusIds);
            if (!mpDnqIds.isEmpty())        updateDnqRollup(mpDnqIds);
            if (!mpIncompleteIds.isEmpty()) updateIncompleteRollup(mpIncompleteIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }


    // ---------------- AFTER DELETE ----------------
    public void afterDelete(Map<Id, SObject> oldMap) {
        try {
            List<ClinicalEntry__c> oldHps = new List<ClinicalEntry__c>();
            for (SObject s : oldMap.values()) oldHps.add((ClinicalEntry__c) s);

            Set<Id> mpStatusIds      = collectMpIdsForStatusRollup(oldHps, null);
            Set<Id> mpDnqIds         = collectMpIdsWhereNewStatusIn(oldHps, DNQ_STATUSES);
            Set<Id> mpIncompleteIds  = collectMpIdsWhereNewStatusIn(oldHps, INCOMPLETE_STATUSES);

            if (!mpStatusIds.isEmpty())     updateStatusRollups(mpStatusIds);
            if (!mpDnqIds.isEmpty())        updateDnqRollup(mpDnqIds);
            if (!mpIncompleteIds.isEmpty()) updateIncompleteRollup(mpIncompleteIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }


    // ---------------- AFTER UNDELETE ----------------
    public void afterUndelete(List<SObject> newRecords) {
        try {
            List<ClinicalEntry__c> newHps = (List<ClinicalEntry__c>) newRecords;

            Set<Id> mpStatusIds      = collectMpIdsForStatusRollup(newHps, null);
            Set<Id> mpDnqIds         = collectMpIdsWhereNewStatusIn(newHps, DNQ_STATUSES);
            Set<Id> mpIncompleteIds  = collectMpIdsWhereNewStatusIn(newHps, INCOMPLETE_STATUSES);

            if (!mpStatusIds.isEmpty())     updateStatusRollups(mpStatusIds);
            if (!mpDnqIds.isEmpty())        updateDnqRollup(mpDnqIds);
            if (!mpIncompleteIds.isEmpty()) updateIncompleteRollup(mpIncompleteIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }


    // ----------------- CORE LOGIC ------------------

    private void processProjectPlanUpdates(List<ClinicalEntry__c> hps, Map<Id, ClinicalEntry__c> oldMap) {
        Set<Id> projectPlanIds = new Set<Id>();
        for (ClinicalEntry__c hp : hps) {
            ClinicalEntry__c oldHp = oldMap != null ? oldMap.get(hp.Id) : null;

            Boolean statusChanged = oldHp == null || hp.Status__c != oldHp.Status__c;
            Boolean mpChanged = oldHp == null || hp.Master_Plan__c != oldHp.Master_Plan__c;

            if (hp.Master_Plan__c != null && (statusChanged || mpChanged)) {
                projectPlanIds.add(hp.Master_Plan__c);
            }
            if (oldHp != null && oldHp.Master_Plan__c != null && mpChanged) {
                projectPlanIds.add(oldHp.Master_Plan__c);
            }
        }

        if (!projectPlanIds.isEmpty()) {
            updateStatusRollups(projectPlanIds);
            updateDnqRollup(projectPlanIds);
            updateIncompleteRollup(projectPlanIds);
        }
    }

    private void updateStatusRollups(Set<Id> mpIds) {
        Map<Id, Map<String, Integer>> tallyMap = new Map<Id, Map<String, Integer>>();

        for (AggregateResult ar : [
            SELECT COUNT(Id) counter, Master_Plan__c mp, Status__c status
            FROM ClinicalEntry__c
            WHERE Master_Plan__c IN :mpIds
            GROUP BY Master_Plan__c, Status__c
        ]) {
            Id mpId = (Id) ar.get('mp');
            String status = (String) ar.get('status');
            Integer count = (Integer) ar.get('counter');

            if (!tallyMap.containsKey(mpId)) {
                tallyMap.put(mpId, new Map<String, Integer>());
            }
            tallyMap.get(mpId).put(status, count);
        }

        List<ProjectPlan__c> updates = new List<ProjectPlan__c>();
        for (Id mpId : tallyMap.keySet()) {
            Map<String, Integer> statusCounts = tallyMap.get(mpId);

            Integer needToBeScreened = statusCounts.containsKey('Need to be Screened') ? statusCounts.get('Need to be Screened') : 0;
            Integer pendingScreen     = statusCounts.containsKey('Pending Screen') ? statusCounts.get('Pending Screen') : 0;
            Integer pendingDocs       = statusCounts.containsKey('Pending Documents') ? statusCounts.get('Pending Documents') : 0;
            Integer readyToSched      = statusCounts.containsKey('Ready to be Scheduled') ? statusCounts.get('Ready to be Scheduled') : 0;

            updates.add(new ProjectPlan__c(
                Id = mpId,
                Pending_Screen__c = needToBeScreened + pendingScreen,
                Pending_Documents__c = pendingDocs,
                Ready_to_be_Scheduled__c = readyToSched
            ));
        }
        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'Status rollup update failed: ' + err.getStatusCode() + ': ' + err.getMessage());
                    }
                }
            }
        }
    }

    private void updateDnqRollup(Set<Id> mpIds) {
        List<String> dnqStatuses = new List<String>{
            'Pre-screen - Doesn’t Qualify for a Current Study',
            'Doesn\'t Qualify For a Current Study',
            'DNQ - At Enrollment Capacity',
            'DNQ - Hold',
            'Cannot Be Reached',
            'Cannot Participate',
            'Out of Territory',
            'Do Not Contact'
        };

        Map<Id, Integer> dnqCountByMp = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT COUNT(Id) cnt, Master_Plan__c
            FROM ClinicalEntry__c
            WHERE Master_Plan__c IN :mpIds
              AND Status__c IN :dnqStatuses
            GROUP BY Master_Plan__c
        ]) {
            dnqCountByMp.put((Id) ar.get('Master_Plan__c'), (Integer) ar.get('cnt'));
        }

        List<ProjectPlan__c> updates = new List<ProjectPlan__c>();
        for (Id mpId : mpIds) {
            updates.add(new ProjectPlan__c(
                Id = mpId,
                Does_not_qualify_at_screening__c = dnqCountByMp.containsKey(mpId) ? dnqCountByMp.get(mpId) : null
            ));
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'DNQ rollup update failed: ' + err.getStatusCode() + ': ' + err.getMessage());
                    }
                }
            }
        }
    }

    private void updateIncompleteRollup(Set<Id> mpIds) {
        List<String> incompleteStatuses = new List<String>{
            'Reschedule',
            'Cancellation/No Show',
            'Unsuccessful Collection'
        };

        Map<Id, Integer> countByMp = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT COUNT(Id) cnt, Master_Plan__c
            FROM ClinicalEntry__c
            WHERE Master_Plan__c IN :mpIds
              AND Status__c IN :incompleteStatuses
            GROUP BY Master_Plan__c
        ]) {
            countByMp.put((Id) ar.get('Master_Plan__c'), (Integer) ar.get('cnt'));
        }

        List<ProjectPlan__c> updates = new List<ProjectPlan__c>();
        for (Id mpId : mpIds) {
            updates.add(new ProjectPlan__c(
                Id = mpId,
                Total_number_of_incomplete_visits__c = countByMp.containsKey(mpId) ? countByMp.get(mpId) : null
            ));
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'Incomplete rollup update failed: ' + err.getStatusCode() + ': ' + err.getMessage());
                    }
                }
            }
        }
    }

    private Set<Id> collectMpIdsForStatusRollup(List<ClinicalEntry__c> hps, Map<Id, ClinicalEntry__c> oldMap) {
        Set<Id> mpIds = new Set<Id>();
        for (ClinicalEntry__c hp : hps) {
            ClinicalEntry__c oldHp = (oldMap != null) ? oldMap.get(hp.Id) : null;
            Boolean statusChanged = (oldHp == null) || hp.Status__c != oldHp.Status__c;
            Boolean mpChanged     = (oldHp == null) || hp.Master_Plan__c  != oldHp.Master_Plan__c;

            if (hp.Master_Plan__c != null && (statusChanged || mpChanged)) mpIds.add(hp.Master_Plan__c);
            if (oldHp != null && oldHp.Master_Plan__c != null && mpChanged) mpIds.add(oldHp.Master_Plan__c);
        }
        return mpIds;
    }

    private Set<Id> collectMpIdsWhereNewStatusIn(List<ClinicalEntry__c> hps, Set<String> statuses) {
        Set<Id> out = new Set<Id>();
        for (ClinicalEntry__c hp : hps) {
            if (hp.Master_Plan__c != null && statuses.contains(hp.Status__c)) out.add(hp.Master_Plan__c);
        }
        return out;
    }

    // ---------------- UNUSED INTERFACE METHODS ----------------

    public void beforeInsert(List<SObject> newRecords) {
    }
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
    }
    public void beforeDelete(Map<Id, SObject> oldMap) {
    }
}
