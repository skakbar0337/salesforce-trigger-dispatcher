/**
 * Trigger handler for CollectionRequest__c.
 * Sets helper checkbox fields when Screening Comments or Collection Comments
 * text area fields are modified, enabling the Combined Alerts flow to detect changes.
 */
public with sharing class CollectionRequestCommentHandler implements ITriggerHandler {

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        for (SObject rec : newRecords) {
            CollectionRequest__c newAR = (CollectionRequest__c) rec;
            CollectionRequest__c oldAR = (CollectionRequest__c) oldRecordsMap.get(newAR.Id);

            newAR.Screening_Comments_Updated__c = (newAR.Screening_Comments__c != oldAR.Screening_Comments__c);
            newAR.Collection_Comments_Updated__c = (newAR.Collection_Comments__c != oldAR.Collection_Comments__c);
        }
    }

    // Empty stubs for unused contexts
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void afterDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
