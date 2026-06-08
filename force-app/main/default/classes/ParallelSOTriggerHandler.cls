/**
 * Trigger handler for ServiceOrder__c.
 * When status changes to Incomplete, clears all member SOs
 * (Parallel_Processed, Parallel_SO_Initiated) and deletes junction members.
 */
public with sharing class ParallelSOTriggerHandler implements ITriggerHandler {

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        List<ServiceOrder__c> incompleteGroups = new List<ServiceOrder__c>();

        for (SObject rec : newRecords) {
            ServiceOrder__c newPSO = (ServiceOrder__c) rec;
            ServiceOrder__c oldPSO = (ServiceOrder__c) oldRecordsMap.get(newPSO.Id);

            if (newPSO.Parallel_SO_Status__c == 'Incomplete'
                && oldPSO.Parallel_SO_Status__c != 'Incomplete') {
                incompleteGroups.add(newPSO);
            }
        }

        for (ServiceOrder__c pso : incompleteGroups) {
            ParallelSOService.unparallelGroup(pso.Id);
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
