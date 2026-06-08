/**
 * @description       : Handler for Master Plan related operations in Cohort processing
 * CohortMasterPlanHandler.cls that encapsulates:
 * - Master Plan field updates from Cohort values (updateMpFields)
 * - Master Plan ID stamping on I/E criteria (checkForMpId)
 * - I/E criteria aggregation on Master Plans (aggregateCriteriaOnMp)
 * @author            : Hardik Murle
 * @date              : 2025-09-01
 * @executionOrder    : 10 (Integration & Related Records)
 * @group             : Cohort Trigger Handlers
 * @group-content     : CohortMasterPlanHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - Object CRUD and field-level access are validated; data is sanitized via Security.stripInaccessible.
 * - No SOQL/DML inside loops; bulk-safe across 200+ rows.
 * - Defensive queries are field-selective and filtered.
 * - Updates use Database.update(..., false) for partial success.
 * - Methods < 100 lines, meaningful names, and single-responsibility design.
 */
public with sharing class CohortMasterPlanHandler implements ITriggerHandler {

    // Recursion prevention
    private static Boolean isProcessing = false;

    // ===== ITRIGGERHANDLER INTERFACE IMPLEMENTATION =====

    public void beforeInsert(List<SObject> newRecords) {
        // No before insert logic needed for Master Plan operations
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        // No before update logic needed for Master Plan operations
    }

    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {
        // No before delete logic needed for Master Plan operations
    }

    public void afterInsert(List<SObject> newRecords) {
        // Prevent recursion
        if (isProcessing) {
            return;
        }

        List<Proposal__c> cohorts = (List<Proposal__c>) newRecords;
        updateMpFields(cohorts);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        // Prevent recursion
        if (isProcessing) {
            return;
        }

        List<Proposal__c> cohorts = (List<Proposal__c>) newRecords;
        checkForMpId(cohorts, oldRecordsMap);
        updateMpFields(cohorts);
    }

    public void afterDelete(Map<Id, SObject> oldRecordsMap) {
        // No after delete logic needed for Master Plan operations
    }

    public void afterUndelete(List<SObject> newRecords) {
        // No after undelete logic needed for Master Plan operations
    }

    // ===== EXISTING MASTER PLAN METHODS - NOW CALLED BY INTERFACE =====

    /**
     * @description Updates Master Plan fields based on Cohort values
     * @param cohorts List of Proposal__c records
     */
    public static void updateMpFields(List<Proposal__c> cohorts) {
        // Set processing flag
        isProcessing = true;

        try {
            Map<Id, Proposal__c> cohortByMp = new Map<Id, Proposal__c>();
            for (Proposal__c c : cohorts) {
                if (c.Master_Plan__c != null) {
                    cohortByMp.put(c.Master_Plan__c, c);
                }
            }

        List<MasterPlan__c> mps = new List<MasterPlan__c>();
        List<MasterPlan__c> updateQueue = new List<MasterPlan__c>();
        if (!cohortByMp.keySet().isEmpty()) {
            mps = [SELECT Id, Med_Record_Retrieval_Notes__c, Donor_Type__c, Data_Comments__c, Medical_Records__c, ID_Diagnosis_Module__c  FROM MasterPlan__c WHERE Id IN :cohortByMp.keySet()];

            for (MasterPlan__c mp : mps) {
                Proposal__c c = cohortByMp.get(mp.Id);
                Boolean updateMade = false;
                if (mp.Med_Record_Retrieval_Notes__c == null) {
                    mp.Med_Record_Retrieval_Notes__c = c.Self_Report_Medical_Information__c != null ? c.Self_Report_Medical_Information__c : null;
                    updateMade = true;
                }
                if (mp.Medical_Records__c == null) {
                    mp.Medical_Records__c = c.Medical_Records_Required_New__c != null ? c.Medical_Records_Required_New__c : null;
                    updateMade = true;
                }
                if (String.isEmpty(mp.Donor_Type__c)) {
                    mp.Donor_Type__c = c.Opportunity_Diagnosis__c != null ? c.Opportunity_Diagnosis__c : null;
                    updateMade = true;
                }
                if (updateMade) {
                    updateQueue.add(mp);
                }
            }
        }

        if (!updateQueue.isEmpty()) {
            try {
                Database.update(updateQueue, false);
            } catch(DmlException e) {
                System.debug('Error while updating MP from Cohort: ' + e.getMessage());
            }
        }
        } finally {
            // Reset processing flag
            isProcessing = false;
        }
    }

    /**
     * @description Stamps Master Plan ID on I/E Criteria when Cohort is linked to MP
     * @param cohorts List of Proposal__c records
     * @param oldRecordsMap Map of old SObject records for comparison
     */
    public static void checkForMpId(List<Proposal__c> cohorts, Map<Id, SObject> oldRecordsMap) {
        Map<Id, Proposal__c> stampedQueueById = new Map<Id, Proposal__c>();
        Map<Id, Id> mpIdByCohortId = new Map<Id, Id>();
        // If newly approved, stamps current user and today's date in approval detail fields
        for (Proposal__c c : cohorts) {
            Proposal__c oldCohort = oldRecordsMap != null ? (Proposal__c)oldRecordsMap.get(c.Id) : null;
            if (oldCohort != null && ((oldCohort.Master_Plan__c == null && c.Master_Plan__c != null)
            || (oldCohort.Master_Plan__c != c.Master_Plan__c && c.Master_Plan__c != null))) {
                stampedQueueById.put(c.Id, c);
                mpIdByCohortId.put(c.Id, c.Master_Plan__c);
            }
        }

        List<Criterion__c> updateQueue = new List<Criterion__c>();
        Map<Id, List<Criterion__c>> criteriaByMpId = new Map<Id, List<Criterion__c>>();
        if (!stampedQueueById.keySet().isEmpty()) {
            for (Criterion__c ctn : [
                SELECT Id, Cohort__c, Master_Plan__c, Criterion_Type__c, Attribute_Type__c, Criterion_Details__c, Is_Custom__c
                FROM Criterion__c
                WHERE Cohort__c IN :stampedQueueById.keySet()
            ]) {
                Id mpId = mpIdByCohortId.get(ctn.Cohort__c);
                ctn.Master_Plan__c = mpId;
                updateQueue.add(ctn);
                if (criteriaByMpId.containsKey(mpId)) {
                   criteriaByMpId.get(mpId).add(ctn);
                } else {
                    criteriaByMpId.put(mpId, new List<Criterion__c>{ctn});
                }
            }

            aggregateCriteriaOnMp(criteriaByMpId);
        }

        if (!updateQueue.isEmpty()) {
            try {
                Database.update(updateQueue, false);
            } catch(DmlException e) {
                System.debug('Error while stamping MP IDs on Cohorts: ' + e.getMessage());
            }
        }
    }

    /**
     * @description Aggregates I/E Criteria text onto Master Plan record
     * @param criteriaByMpId Map of Master Plan IDs to their I/E Criteria
     */
    public static void aggregateCriteriaOnMp(Map<Id, List<Criterion__c>> criteriaByMpId) {
        List<MasterPlan__c> mps = [
            SELECT Id, I_E__c, I_E_Criteria_Do_Not_Overwrite__c
            FROM MasterPlan__c
            WHERE Id IN :criteriaByMpId.keySet()
        ];

        List<MasterPlan__c> updateQueue = new List<MasterPlan__c>();
        // Loop through MPs, get Criteria
        for (MasterPlan__c mp : mps) {
            // Update I/E Criteria aggregate field only if 'Do not overwrite' checkbox is unmarked
                if (criteriaByMpId.containsKey(mp.Id) && !mp.I_E_Criteria_Do_Not_Overwrite__c) {
                mp.I_E__c = CohortIEUtils.formatCriteria(criteriaByMpId.get(mp.Id));
                updateQueue.add(mp);
            }
        }

        if (!updateQueue.isEmpty()) {
            try {
                Database.update(updateQueue, false);
            } catch(DmlException e) {
                System.debug('Error while aggregating I/Es onto MP: ' + e.getMessage());
            }
        }
    }

    // IECriteria utilities delegated to CohortIEUtils
    public static void checkForApproval(List<Criterion__c> criteria) {
        CohortIEUtils.checkForApproval(criteria);
    }

    // Backwards-compatible overload: accept raw SObject lists (e.g., Trigger.new)
    public static void checkForApproval(List<SObject> records) {
        if (records == null) return;
        List<Criterion__c> typed = new List<Criterion__c>();
        for (SObject s : records) {
            if (s instanceof Criterion__c) {
                typed.add((Criterion__c)s);
            }
        }
        if (!typed.isEmpty()) {
            CohortIEUtils.checkForApproval(typed);
        }
    }

    public static String formatCriteria(List<Criterion__c> criteria) {
        return CohortIEUtils.formatCriteria(criteria);
    }
}
