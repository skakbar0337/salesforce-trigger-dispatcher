trigger Notification_Message_Trigger on Notification__c (after insert) {
    TriggerDispatcher.dispatch('Notification__c');
}