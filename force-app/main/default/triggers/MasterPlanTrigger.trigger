trigger MasterPlanTrigger on MasterPlan__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {
        TriggerDispatcher.dispatch('MasterPlan__c');
    }

    // Refactored to MasterPlanBusinessHandler (order 40) via TriggerDispatcher
    // if (Trigger.IsBefore && trigger.isInsert) {
    //     MasterPlanHelper.doBeforeInsert(Trigger.new);
    // }

    // Refactored to MasterPlanRealTimeExportHandler (order 90) via TriggerDispatcher
    // integrator_da__.RealTimeExportResult res = integrator_da__.RealTimeExporter.processExport();

    // Refactored to MasterPlanBusinessHandler (order 40) via TriggerDispatcher
    // if (Trigger.isUpdate && trigger.isAfter) {
    //     MasterPlanHelper.doAfterUpdate(Trigger.New, trigger.oldMap);
    //     // VisitProjectionService.processMps(Trigger.New);
    // }
    // if (Trigger.isDelete && trigger.isAfter) {
    //     MasterPlanHelper.doAfterDelete(Trigger.old);
    // }
    // if (Trigger.isUndelete && trigger.isAfter) {
    //     MasterPlanHelper.doAfterUndelete(Trigger.New);
    // }

    if (Trigger.isAfter) {
        TriggerDispatcher.dispatch('MasterPlan__c');
    }
}