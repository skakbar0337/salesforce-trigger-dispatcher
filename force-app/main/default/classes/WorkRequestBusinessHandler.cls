/**
 * @description Business logic for WorkRequest__c: PO/service line creation,
 *              master plan rollups, patient updates, Smartsheet integration, Skedulo check.
 * @executionOrder 50 (Complex Business Logic)
 */
public with sharing class WorkRequestBusinessHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'WorkRequestBusinessHandler';

    public void afterInsert(List<SObject> newRecords) {
        try {
            List<WorkRequest__c> listy = new List<WorkRequest__c>();
            for (SObject s : newRecords) listy.add((WorkRequest__c) s);

            WorkRequestLib.createPurchaseOrderLine(listy);
            WorkRequestLib.createServiceOrderLine(listy);
            WorkRequestLib.rollupProjectPlanFields(listy, null);
            WorkRequestLib.updatePatientAndSmartsheet(listy, null);
            WorkRequestLib.checkOrderStatus(listy);
            SkeduloService.checkCriteria(listy);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<WorkRequest__c> newList = new List<WorkRequest__c>();
            for (SObject s : newRecords) newList.add((WorkRequest__c) s);

            Map<Id, WorkRequest__c> oldTyped = new Map<Id, WorkRequest__c>();
            if (oldMap != null) {
                for (Id k : oldMap.keySet()) oldTyped.put(k, (WorkRequest__c) oldMap.get(k));
            }

            WorkRequestLib.doAfterUpdate(newList, oldTyped);
            WorkRequestLib.checkOrderStatus(newList);
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
