trigger ApheresisRequestTrigger on ServiceRequest__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    TriggerDispatcher.dispatch('ServiceRequest__c');
}