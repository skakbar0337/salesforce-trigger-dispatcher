public with sharing class AuditEntryHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'AuditEntryHandler';

    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {}

    public void afterInsert(List<SObject> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) return;
        try {
            List<AuditEntry__c> items = new List<AuditEntry__c>();
            for (SObject s : newRecords) items.add((AuditEntry__c) s);
            stampOrderWithItemId(items);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void afterDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterUndelete(List<SObject> newRecords) {}

    public static void stampOrderWithItemId(List<AuditEntry__c> items) {
        if (items == null || items.isEmpty()) return;

        Map<Id, Id> reportItemIdsByOrderId = new Map<Id, Id>();
        for (AuditEntry__c i : items) {
            if (i.Purchase_Order__c != null) {
                reportItemIdsByOrderId.put(i.Purchase_Order__c, i.Id);
            }
        }

        if (reportItemIdsByOrderId.isEmpty()) return;

        List<WorkRequest__c> orderToUpdate = new List<WorkRequest__c>();
        for (WorkRequest__c po : [
            SELECT Id, Report_Item_ID__c
            FROM   WorkRequest__c
            WHERE  Id IN :reportItemIdsByOrderId.keySet()
        ]) {
            po.Report_Item_ID__c = reportItemIdsByOrderId.get(po.Id);
            orderToUpdate.add(po);
        }

        if (!orderToUpdate.isEmpty()) {
            try {
                Database.update(orderToUpdate, false);
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, e.getMessage());
            }
        }
    }
}
