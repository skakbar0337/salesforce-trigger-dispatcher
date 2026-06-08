trigger AuditEntryTrigger on AuditEntry__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    TriggerDispatcher.dispatch('AuditEntry__c');
}