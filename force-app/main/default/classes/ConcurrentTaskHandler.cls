/**
 * Trigger handler for ExternalOrder__c.
 * When status changes to Incomplete, clears all member SOs
 * (Parallel_Processed, Parallel_SO_Initiated) and deletes junction members.
 */
public with sharing class ConcurrentTaskHandler implements ITriggerHandler {

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        List<ExternalOrder__c> incompleteGroups = new List<ExternalOrder__c>();

        for (SObject rec : newRecords) {
            ExternalOrder__c newPSO = (ExternalOrder__c) rec;
            ExternalOrder__c oldPSO = (ExternalOrder__c) oldRecordsMap.get(newPSO.Id);

            if (newPSO.Parallel_SO_Status__c == 'Incomplete'
                && oldPSO.Parallel_SO_Status__c != 'Incomplete') {
                incompleteGroups.add(newPSO);
            }
        }

        for (ExternalOrder__c pso : incompleteGroups) {
            ConcurrentTaskService.unparallelGroup(pso.Id);
        }
    }

    // Empty stubs for unused contexts
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
