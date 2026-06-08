trigger Partner_Supply_Request_Trigger on SupplyRequest__c (after insert, after update) {
    TriggerDispatcher.dispatch('SupplyRequest__c');
}