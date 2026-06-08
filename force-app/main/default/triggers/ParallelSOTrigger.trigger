trigger ParallelSOTrigger on ServiceOrder__c (before insert, before update, before delete,
    after insert, after update, after delete, after undelete)
{
    TriggerDispatcher.dispatch('ServiceOrder__c');
}