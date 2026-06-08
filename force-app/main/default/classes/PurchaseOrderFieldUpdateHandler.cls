/**
 * @description Field updates and completion-date stamping for PurchaseOrder__c.
 * @executionOrder 30 (Field Defaults & Updates)
 */
public with sharing class PurchaseOrderFieldUpdateHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'PurchaseOrderFieldUpdateHandler';

    public void beforeInsert(List<SObject> newRecords) {
        try {
            List<PurchaseOrder__c> poList = new List<PurchaseOrder__c>();
            for (SObject s : newRecords) poList.add((PurchaseOrder__c) s);
            PurchaseOrderLib.updateOrderField(poList, null);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<PurchaseOrder__c> newList = new List<PurchaseOrder__c>();
            for (SObject s : newRecords) newList.add((PurchaseOrder__c) s);

            Map<Id, PurchaseOrder__c> oldTyped = new Map<Id, PurchaseOrder__c>();
            if (oldMap != null) {
                for (Id k : oldMap.keySet()) oldTyped.put(k, (PurchaseOrder__c) oldMap.get(k));
            }

            PurchaseOrderLib.updateOrderField(newList, oldTyped);
            PurchaseOrderLib.checkForCompletion(newList, oldTyped);
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
