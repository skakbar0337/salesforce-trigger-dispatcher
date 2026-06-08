trigger ReportItemTrigger on ReportItem__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    TriggerDispatcher.dispatch('ReportItem__c');
}