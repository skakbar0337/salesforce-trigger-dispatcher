trigger CohortTrigger on Proposal__c (after insert, before insert, after delete, after update,
                                      after undelete, before delete, before update) {
    TriggerDispatcher.dispatch('Proposal__c');
}