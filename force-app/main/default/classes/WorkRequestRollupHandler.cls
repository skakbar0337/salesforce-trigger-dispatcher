/**
 * @description Handles delete/undelete rollups, projections, email notifications,
 *              and patient/Smartsheet updates for WorkRequest__c.
 * @executionOrder 70 (Rollup & Cleanup)
 */
public with sharing class WorkRequestRollupHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'WorkRequestRollupHandler';

    public void afterDelete(Map<Id, SObject> oldMap) {
        try {
            List<WorkRequest__c> oldOrders = new List<WorkRequest__c>();
            if (oldMap != null) {
                for (SObject sob : oldMap.values()) oldOrders.add((WorkRequest__c) sob);
            }

            WorkRequestLib.rollupProjectPlanFields(oldOrders, null);
            WorkRequestLib.visitProjectionOrderedRollup(oldOrders);
            WorkRequestLib.visitProjectionCompletedRollup(oldOrders);
            WorkRequestLib.sendEmailOnorderDeletion(oldOrders);
            WorkRequestLib.updatePatientAndSmartsheet(oldOrders, null);
            WorkRequestLib.checkOrderStatus(oldOrders, true);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUndelete(List<SObject> newRecords) {
        try {
            List<WorkRequest__c> newList = new List<WorkRequest__c>();
            for (SObject s : newRecords) newList.add((WorkRequest__c) s);

            WorkRequestLib.rollupProjectPlanFields(newList, null);
            WorkRequestLib.visitProjectionOrderedRollup(newList);
            WorkRequestLib.updatePatientAndSmartsheet(newList, null);
            WorkRequestLib.visitProjectionCompletedRollup(newList);
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