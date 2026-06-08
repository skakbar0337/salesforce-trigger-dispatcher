trigger SubjectGroupTrigger on BidRecord__c (after insert, before insert, after delete, after update,
                                      after undelete, before delete, before update) {
    TriggerDispatcher.dispatch('BidRecord__c');
}