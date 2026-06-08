/**
 * Portal_DocumentVisibilityHandler
 *
 * Forces ContentDocumentLink.Visibility = 'AllUsers' when an internal user
 * uploads a file to a ProjectRequest__c or SupplyRequest__c,
 * so the file becomes visible to Experience Cloud partner users.
 *
 * Salesforce's default visibility for files uploaded via the standard
 * "Notes & Attachments" UI is 'InternalUsers', which hides the row from
 * portal users at the platform query layer. This before-insert override
 * eliminates the manual "Set Sharing → External" step.
 *
 * Registered via TriggerHandlerConfig.Portal_Document_Visibility_Handler
 * (SObjectName__c = 'ContentDocumentLink', ExecutionOrder__c = 5).
 */
public without sharing class Portal_DocumentVisibilityHandler implements ITriggerHandler {

    public void beforeInsert(List<SObject> newRecords) {
        for (SObject record : newRecords) {
            ContentDocumentLink cdl = (ContentDocumentLink) record;
            if (cdl.LinkedEntityId == null) continue;
            Schema.SObjectType entityType = cdl.LinkedEntityId.getSObjectType();
            if (entityType == ProjectRequest__c.SObjectType
                    || entityType == SupplyRequest__c.SObjectType) {
                cdl.Visibility = 'AllUsers';
            }
        }
    }

    public void afterInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
