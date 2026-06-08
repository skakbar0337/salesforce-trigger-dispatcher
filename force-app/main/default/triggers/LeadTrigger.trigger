trigger LeadTrigger on Lead (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {
        TriggerDispatcher.dispatch('Lead');
    }

    // Refactored to LeadMarketingHandler (order 20) and LeadQualificationHandler (order 40) via TriggerDispatcher
    // if (trigger.isUpdate && trigger.isAfter) {
    //     LeadTriggerHelper.doAfterUpdate(trigger.new, trigger.oldMap);
    // }
    // if (trigger.isInsert && trigger.isAfter) {
    //     LeadTriggerHelper.doAfterInsert(Trigger.new);
    // }

    if (Trigger.isAfter) {
        TriggerDispatcher.dispatch('Lead');
    }
}