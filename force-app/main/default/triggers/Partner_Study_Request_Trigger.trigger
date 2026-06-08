trigger Partner_Study_Request_Trigger on StudyRequest__c (after insert, after update) {
    TriggerDispatcher.dispatch('StudyRequest__c');
}