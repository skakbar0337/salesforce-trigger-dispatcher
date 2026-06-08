trigger ManageWorkRequests on WorkRequest__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {
        TriggerDispatcher.dispatch('WorkRequest__c');
    }

    // Refactored to WorkRequestFieldHandler (order 30), WorkRequestBusinessHandler (order 50),
    // and WorkRequestRollupHandler (order 70) via TriggerDispatcher
    // if (Trigger.isBefore && Trigger.isInsert) { SpecimenOrderHelper.doBeforeInsert(trigger.New); }
    // if (Trigger.isUpdate && Trigger.isBefore) { SpecimenOrderHelper.doBeforeUpdate(trigger.New, trigger.OldMap); }
    // if (Trigger.isAfter && Trigger.isInsert) { SpecimenOrderHelper.doAfterInsert(trigger.New); }
    // if (Trigger.isAfter && Trigger.isUpdate) { SpecimenOrderHelper.doAfterUpdate(trigger.New, trigger.OldMap); }
    // if (Trigger.isAfter && (Trigger.isUpdate || Trigger.isInsert)) { SpecimenOrderHelper.checkOrderStatus(Trigger.new); }
    // if (Trigger.isDelete && Trigger.isAfter) { SpecimenOrderHelper.doAfterDelete(trigger.old); }
    // if (Trigger.isAfter && Trigger.isUndelete) { SpecimenOrderHelper.doAfterUnDelete(trigger.New); }

    if (Trigger.isAfter) {
        TriggerDispatcher.dispatch('WorkRequest__c');
    }
}