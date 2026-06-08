public without sharing class Portal_MessageEmailHandler implements ITriggerHandler {

    public void afterInsert(List<SObject> newRecords) {
        Set<Id> psrIds = new Set<Id>();
        for (SObject record : newRecords) {
            Notification__c msg = (Notification__c) record;
            if (String.isNotBlank(msg.Record_Id__c)) {
                try {
                    Id recordId = (Id) msg.Record_Id__c;
                    if (recordId.getSObjectType() == ProjectRequest__c.SObjectType) {
                        psrIds.add(recordId);
                    }
                } catch (Exception e) {
                    // Record_Id__c is not a valid Id — skip
                }
            }
        }

        if (psrIds.isEmpty()) return;

        Map<Id, ProjectRequest__c> psrMap = new Map<Id, ProjectRequest__c>([
            SELECT Id, Name, Study_Name__c, Site_Code__c
            FROM ProjectRequest__c
            WHERE Id IN :psrIds
        ]);

        for (SObject record : newRecords) {
            Notification__c msg = (Notification__c) record;
            if (String.isBlank(msg.Record_Id__c)) continue;

            Id recordId;
            try {
                recordId = (Id) msg.Record_Id__c;
            } catch (Exception e) {
                continue;
            }

            ProjectRequest__c psr = psrMap.get(recordId);
            if (psr == null) continue;

            List<Portal_EmailNotificationService.CoordinatorInfo> coords =
                Portal_EmailNotificationService.resolveCoordinatorInfos(psr.Site_Code__c);

            if (msg.Sender_Type__c == 'Internal') {
                // EN-09: site-facing — fan out to every assigned partner coordinator
                for (Portal_EmailNotificationService.CoordinatorInfo c : coords) {
                    Portal_EmailNotificationService.sendNewMessageFromProvider(msg, psr, c);
                }
            } else if (msg.Sender_Type__c == 'Portal User') {
                // EN-10: ops-facing — single recipient
                Portal_EmailNotificationService.sendNewMessageFromSite(
                    msg, psr, coords.isEmpty() ? null : coords[0]
                );
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
