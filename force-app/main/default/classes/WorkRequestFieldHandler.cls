/**
 * @description Field updates and completion-date stamping for WorkRequest__c.
 * @executionOrder 30 (Field Defaults & Updates)
 */
public with sharing class WorkRequestFieldHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'WorkRequestFieldHandler';

    public void beforeInsert(List<SObject> newRecords) {
        try {
            List<WorkRequest__c> poList = new List<WorkRequest__c>();
            for (SObject s : newRecords) poList.add((WorkRequest__c) s);
            WorkRequestLib.updateOrderField(poList, null);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<WorkRequest__c> newList = new List<WorkRequest__c>();
            for (SObject s : newRecords) newList.add((WorkRequest__c) s);

            Map<Id, WorkRequest__c> oldTyped = new Map<Id, WorkRequest__c>();
            if (oldMap != null) {
                for (Id k : oldMap.keySet()) oldTyped.put(k, (WorkRequest__c) oldMap.get(k));
            }

            WorkRequestLib.updateOrderField(newList, oldTyped);
            WorkRequestLib.checkForCompletion(newList, oldTyped);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
