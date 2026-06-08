public without sharing class PP_DocumentEmailHandler implements ITriggerHandler {

    public void afterInsert(List<SObject> newRecords) {
        for (SObject record : newRecords) {
            ContentDocumentLink cdl = (ContentDocumentLink) record;
            Schema.SObjectType entityType = cdl.LinkedEntityId.getSObjectType();
            if (entityType == StudyRequest__c.SObjectType
                    || entityType == DonorRequest__c.SObjectType) {
                System.enqueueJob(new PP_DocumentEmailQueueable(cdl.Id));
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
