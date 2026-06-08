trigger ManagePurchaseOrders on PurchaseOrder__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {
        TriggerDispatcher.dispatch('PurchaseOrder__c');
    }

    // Refactored to PurchaseOrderFieldUpdateHandler (order 30), PurchaseOrderBusinessHandler (order 50),
    // and PurchaseOrderRollupHandler (order 70) via TriggerDispatcher
    // if (Trigger.isBefore && Trigger.isInsert) { SpecimenOrderHelper.doBeforeInsert(trigger.New); }
    // if (Trigger.isUpdate && Trigger.isBefore) { SpecimenOrderHelper.doBeforeUpdate(trigger.New, trigger.OldMap); }
    // if (Trigger.isAfter && Trigger.isInsert) { SpecimenOrderHelper.doAfterInsert(trigger.New); }
    // if (Trigger.isAfter && Trigger.isUpdate) { SpecimenOrderHelper.doAfterUpdate(trigger.New, trigger.OldMap); }
    // if (Trigger.isAfter && (Trigger.isUpdate || Trigger.isInsert)) { SpecimenOrderHelper.checkOrderStatus(Trigger.new); }
    // if (Trigger.isDelete && Trigger.isAfter) { SpecimenOrderHelper.doAfterDelete(trigger.old); }
    // if (Trigger.isAfter && Trigger.isUndelete) { SpecimenOrderHelper.doAfterUnDelete(trigger.New); }

    if (Trigger.isAfter) {
        TriggerDispatcher.dispatch('PurchaseOrder__c');
    }
}