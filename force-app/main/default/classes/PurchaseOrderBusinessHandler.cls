/**
 * @description Business logic for PurchaseOrder__c: PO/service line creation,
 *              master plan rollups, patient updates, Smartsheet integration, Skedulo check.
 * @executionOrder 50 (Complex Business Logic)
 */
public with sharing class PurchaseOrderBusinessHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'PurchaseOrderBusinessHandler';

    public void afterInsert(List<SObject> newRecords) {
        try {
            List<PurchaseOrder__c> listy = new List<PurchaseOrder__c>();
            for (SObject s : newRecords) listy.add((PurchaseOrder__c) s);

            PurchaseOrderLib.createPurchaseOrderLine(listy);
            PurchaseOrderLib.createServiceOrderLine(listy);
            PurchaseOrderLib.rollupMasterPlanFields(listy, null);
            PurchaseOrderLib.updatePatientAndSmartsheet(listy, null);
            PurchaseOrderLib.checkOrderStatus(listy);
            SkeduloService.checkCriteria(listy);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<PurchaseOrder__c> newList = new List<PurchaseOrder__c>();
            for (SObject s : newRecords) newList.add((PurchaseOrder__c) s);

            Map<Id, PurchaseOrder__c> oldTyped = new Map<Id, PurchaseOrder__c>();
            if (oldMap != null) {
                for (Id k : oldMap.keySet()) oldTyped.put(k, (PurchaseOrder__c) oldMap.get(k));
            }

            PurchaseOrderLib.doAfterUpdate(newList, oldTyped);
            PurchaseOrderLib.checkOrderStatus(newList);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
