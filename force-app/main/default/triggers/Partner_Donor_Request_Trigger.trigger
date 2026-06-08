trigger Partner_Donor_Request_Trigger on DonorRequest__c (after insert, after update) {
    TriggerDispatcher.dispatch('DonorRequest__c');
}