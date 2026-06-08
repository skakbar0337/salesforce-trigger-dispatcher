trigger Partner_Project_Request_Trigger on ProjectRequest__c (after insert, after update) {
    TriggerDispatcher.dispatch('ProjectRequest__c');
}