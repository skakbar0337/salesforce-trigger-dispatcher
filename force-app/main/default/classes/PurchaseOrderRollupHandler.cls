/**
 * @description Handles delete/undelete rollups, projections, email notifications,
 *              and patient/Smartsheet updates for PurchaseOrder__c.
 * @executionOrder 70 (Rollup & Cleanup)
 */
public with sharing class PurchaseOrderRollupHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'PurchaseOrderRollupHandler';

    public void afterDelete(Map<Id, SObject> oldMap) {
        try {
            List<PurchaseOrder__c> oldOrders = new List<PurchaseOrder__c>();
            if (oldMap != null) {
                for (SObject sob : oldMap.values()) oldOrders.add((PurchaseOrder__c) sob);
            }

            PurchaseOrderLib.rollupMasterPlanFields(oldOrders, null);
            PurchaseOrderLib.visitProjectionOrderedRollup(oldOrders);
            PurchaseOrderLib.visitProjectionCompletedRollup(oldOrders);
            PurchaseOrderLib.sendEmailOnorderDeletion(oldOrders);
            PurchaseOrderLib.updatePatientAndSmartsheet(oldOrders, null);
            PurchaseOrderLib.checkOrderStatus(oldOrders, true);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUndelete(List<SObject> newRecords) {
        try {
            List<PurchaseOrder__c> newList = new List<PurchaseOrder__c>();
            for (SObject s : newRecords) newList.add((PurchaseOrder__c) s);

            PurchaseOrderLib.rollupMasterPlanFields(newList, null);
            PurchaseOrderLib.visitProjectionOrderedRollup(newList);
            PurchaseOrderLib.updatePatientAndSmartsheet(newList, null);
            PurchaseOrderLib.visitProjectionCompletedRollup(newList);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
}