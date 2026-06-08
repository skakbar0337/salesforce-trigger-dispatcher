trigger EligibilityCriteriaTrigger on Criterion__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    TriggerDispatcher.dispatch('Criterion__c');
}