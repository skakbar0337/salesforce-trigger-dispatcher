trigger CaseTrigger on Case (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {
        TriggerDispatcher.dispatch('Case');
    }

    // Legacy CaseTriggerHelper calls - now handled by CMDT-driven handlers
    // if(Trigger.isInsert && trigger.isBefore){
    //     CaseTriggerHelper.doBeforeInsert(Trigger.New);
    // }
    // if(Trigger.isUpdate && trigger.isBefore){
    //     CaseTriggerHelper.doBeforeUpdate(Trigger.New, trigger.oldMap);
    // }
    // if(Trigger.isInsert && trigger.isAfter){
    //     CaseTriggerHelper.doAfterInsert(Trigger.New);
    // }
    // if(Trigger.isUpdate && trigger.isAfter){
    //     CaseTriggerHelper.doAfterUpdate(Trigger.New, trigger.oldMap);
    // }
    // if(Trigger.isDelete && trigger.isAfter){
    //     CaseTriggerHelper.doAfterDelete(Trigger.old);
    // }
    // if(Trigger.isUndelete && trigger.isAfter){
    //     CaseTriggerHelper.doAfterUndelete(Trigger.New);
    // }

    if (Trigger.isAfter) {
        TriggerDispatcher.dispatch('Case');
    }
}