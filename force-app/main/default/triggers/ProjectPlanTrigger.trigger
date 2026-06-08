trigger ProjectPlanTrigger on ProjectPlan__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {
        TriggerDispatcher.dispatch('ProjectPlan__c');
    }

    // Refactored to ProjectPlanBusinessHandler (order 40) via TriggerDispatcher
    // if (Trigger.IsBefore && trigger.isInsert) {
    //     ProjectPlanHelper.doBeforeInsert(Trigger.new);
    // }

    // Refactored to ProjectPlanExportHandler (order 90) via TriggerDispatcher
    // integrator_da__.RealTimeExportResult res = integrator_da__.RealTimeExporter.processExport();

    // Refactored to ProjectPlanBusinessHandler (order 40) via TriggerDispatcher
    // if (Trigger.isUpdate && trigger.isAfter) {
    //     ProjectPlanHelper.doAfterUpdate(Trigger.New, trigger.oldMap);
    //     // VisitProjectionService.processMps(Trigger.New);
    // }
    // if (Trigger.isDelete && trigger.isAfter) {
    //     ProjectPlanHelper.doAfterDelete(Trigger.old);
    // }
    // if (Trigger.isUndelete && trigger.isAfter) {
    //     ProjectPlanHelper.doAfterUndelete(Trigger.New);
    // }

    if (Trigger.isAfter) {
        TriggerDispatcher.dispatch('ProjectPlan__c');
    }
}