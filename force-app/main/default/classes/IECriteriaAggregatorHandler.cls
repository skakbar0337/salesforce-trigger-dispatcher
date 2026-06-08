/**
 * @description       : Handler to aggregate I/E Criteria text onto Cohorts/Master Plans.
 * IECriteriaAggregatorHandler.cls that encapsulates:
 * - Aggregation logic (aggregateOnCohort)
 * @author            : Refactored by Hardik
 * @date              : 2025-09-09
 * @executionOrder    : 20 (Aggregation & Reporting)
 * @group             : IE Criteria Trigger Handlers
 * @group-content     : IECriteriaAggregatorHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class should be executed with appropriate sharing context in callers.
 * - Use Security.stripInaccessible in any DML paths if fields are sensitive.
 * - Bulk-safe: no SOQL/DML inside loops; designed to handle large trigger batches.
 */
public class IECriteriaAggregatorHandler implements ITriggerHandler {

    // Static helper for direct calls (backwards-compatible)
    public static void after(List<Criterion__c> newList) {
        if (newList == null || newList.isEmpty()) return;
        CohortIEUtils.aggregateOnCohort(newList);
    }

    // ITriggerHandler implementation - only after events needed for aggregation
    public void afterInsert(List<SObject> newRecords) {
        List<Criterion__c> typed = (List<Criterion__c>) newRecords;
        after(typed);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        List<Criterion__c> typed = (List<Criterion__c>) newRecords;
        after(typed);
    }

    public void afterUndelete(List<SObject> newRecords) {
        List<Criterion__c> typed = (List<Criterion__c>) newRecords;
        after(typed);
    }

    public void beforeInsert(List<SObject> newRecords) { /* no-op */ }
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) { /* no-op */ }
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) { /* no-op */ }
    public void afterDelete(Map<Id, SObject> oldRecordsMap) { /* no-op */ }
}
