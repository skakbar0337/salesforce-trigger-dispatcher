trigger ConcurrentTaskTrigger on ExternalOrder__c (before insert, before update, before delete,
    after insert, after update, after delete, after undelete)
{
    TriggerDispatcher.dispatch('ExternalOrder__c');
}