public without sharing class Portal_DocumentEmailHandler implements ITriggerHandler {

    public void afterInsert(List<SObject> newRecords) {
        for (SObject record : newRecords) {
            ContentDocumentLink cdl = (ContentDocumentLink) record;
            Schema.SObjectType entityType = cdl.LinkedEntityId.getSObjectType();
            if (entityType == ProjectRequest__c.SObjectType
                    || entityType == SupplyRequest__c.SObjectType) {
                System.enqueueJob(new Portal_DocumentEmailQueueable(cdl.Id));
            }
        }
    }

    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
