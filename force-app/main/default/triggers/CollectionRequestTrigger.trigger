trigger CollectionRequestTrigger on CollectionRequest__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    TriggerDispatcher.dispatch('CollectionRequest__c');
}