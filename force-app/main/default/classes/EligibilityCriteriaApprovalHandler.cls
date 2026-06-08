/**
 * @description       : Handler to stamp approval metadata on I/E Criteria when status is set to Approved.
 * EligibilityCriteriaApprovalHandler.cls that encapsulates:
 * - Approval stamping logic (checkForApproval)
 * @author            : Refactored by Team Developer
 * @date              : 2025-09-09
 * @executionOrder    : 10 (Integration & Related Records)
 * @group             : IE Criteria Trigger Handlers
 * @group-content     : EligibilityCriteriaApprovalHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class should be executed with appropriate sharing context in callers.
 * - Use Security.stripInaccessible in any DML paths if fields are sensitive.
 * - Bulk-safe: no SOQL/DML inside loops; designed to handle large trigger batches.
 */
public class EligibilityCriteriaApprovalHandler implements ITriggerHandler {

    // Static helper for direct calls (backwards-compatible)
    public static void before(List<Criterion__c> newList) {
        if (newList == null || newList.isEmpty()) return;
        SubjectGroupCriteriaUtils.checkForApproval(newList);
    }

    // ITriggerHandler implementation - only before events needed for approval stamping
    public void beforeInsert(List<SObject> newRecords) {
        List<Criterion__c> typed = (List<Criterion__c>) newRecords;
        before(typed);
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        List<Criterion__c> typed = (List<Criterion__c>) newRecords;
        before(typed);
    }

    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {
        // No-op
    }

    public void afterInsert(List<SObject> newRecords) { /* no-op */ }
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) { /* no-op */ }
    public void afterDelete(Map<Id, SObject> oldRecordsMap) { /* no-op */ }
    public void afterUndelete(List<SObject> newRecords) { /* no-op */ }
}
