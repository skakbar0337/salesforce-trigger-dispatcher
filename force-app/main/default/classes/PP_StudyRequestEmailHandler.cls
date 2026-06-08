public without sharing class PP_StudyRequestEmailHandler implements ITriggerHandler {

    private static final Set<String> SANGUINE_STATUS_TRIGGERS = new Set<String>{
        'Publish'
    };
    private static final Set<String> SITE_RESPONSE_STATUS_TRIGGERS = new Set<String>{
        'Pending Review', 'Accepted', 'Declined', 'More Info Requested'
    };
    private static final Set<String> CLIENT_STATUS_TRIGGERS = new Set<String>{
        'Researcher Approved', 'Researcher Declined'
    };

    public void afterInsert(List<SObject> newRecords) {
        Set<Id> publishedIds = new Set<Id>();
        for (SObject record : newRecords) {
            StudyRequest__c psr = (StudyRequest__c) record;
            if (psr.Sanguine_Status__c == 'Publish') {
                publishedIds.add(psr.Id);
            }
        }
        if (publishedIds.isEmpty()) return;

        for (StudyRequest__c psr : queryFullPsrs(publishedIds)) {
            List<PP_EmailNotificationService.CoordinatorInfo> coords =
                PP_EmailNotificationService.resolveCoordinatorInfos(psr.Site_Code__c);
            for (PP_EmailNotificationService.CoordinatorInfo coord : coords) {
                PP_EmailNotificationService.sendNewStudyRequest(psr, coord);
            }
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        Set<Id> idsToFetch = new Set<Id>();
        for (SObject record : newRecords) {
            StudyRequest__c psr    = (StudyRequest__c) record;
            StudyRequest__c oldPsr = (StudyRequest__c) oldRecordsMap.get(psr.Id);
            if (statusChanged(psr, oldPsr)) {
                idsToFetch.add(psr.Id);
            }
        }
        if (idsToFetch.isEmpty()) return;

        Map<Id, StudyRequest__c> fullPsrs = new Map<Id, StudyRequest__c>(
            queryFullPsrs(idsToFetch)
        );

        for (SObject record : newRecords) {
            StudyRequest__c triggerPsr = (StudyRequest__c) record;
            StudyRequest__c psr        = fullPsrs.get(triggerPsr.Id);
            if (psr == null) continue;
            StudyRequest__c oldPsr = (StudyRequest__c) oldRecordsMap.get(psr.Id);

            List<PP_EmailNotificationService.CoordinatorInfo> coords = null;

            // EN-06: entered Pending Review — schedule reminder in 5 minutes
            if (triggerPsr.Site_Response_Status__c == 'Pending Review' && oldPsr.Site_Response_Status__c != 'Pending Review') {
                PP_StudyRequestReminderScheduler.scheduleReminder(psr.Id);
            }

            // EN-02: study published
            if (triggerPsr.Sanguine_Status__c == 'Publish' && oldPsr.Sanguine_Status__c != 'Publish') {
                coords = resolveIfNull(psr, coords);
                for (PP_EmailNotificationService.CoordinatorInfo c : coords) {
                    PP_EmailNotificationService.sendNewStudyRequest(psr, c);
                }
            }

            // EN-03 (site) + EN-13 (ops): site accepted
            if (triggerPsr.Site_Response_Status__c == 'Accepted' && oldPsr.Site_Response_Status__c != 'Accepted') {
                coords = resolveIfNull(psr, coords);
                for (PP_EmailNotificationService.CoordinatorInfo c : coords) {
                    PP_EmailNotificationService.sendStudyAcceptedSite(psr, c);
                }
                PP_EmailNotificationService.sendStudyAcceptedOps(psr, firstOrNull(coords));
            }

            // EN-14 (ops): site declined
            if (triggerPsr.Site_Response_Status__c == 'Declined' && oldPsr.Site_Response_Status__c != 'Declined') {
                coords = resolveIfNull(psr, coords);
                PP_EmailNotificationService.sendStudyDeclinedOps(psr, firstOrNull(coords));
            }

            // EN-16 (ops): site needs more info
            if (triggerPsr.Site_Response_Status__c == 'More Info Requested' && oldPsr.Site_Response_Status__c != 'More Info Requested') {
                coords = resolveIfNull(psr, coords);
                PP_EmailNotificationService.sendNeedMoreInfoOps(psr, firstOrNull(coords));
            }

            // EN-04 (site): researcher approved
            if (triggerPsr.Client_Status__c == 'Researcher Approved' && oldPsr.Client_Status__c != 'Researcher Approved') {
                coords = resolveIfNull(psr, coords);
                for (PP_EmailNotificationService.CoordinatorInfo c : coords) {
                    PP_EmailNotificationService.sendStudyNowActive(psr, c);
                }
            }

            // EN-05 (site): researcher declined
            if (triggerPsr.Client_Status__c == 'Researcher Declined' && oldPsr.Client_Status__c != 'Researcher Declined') {
                coords = resolveIfNull(psr, coords);
                for (PP_EmailNotificationService.CoordinatorInfo c : coords) {
                    PP_EmailNotificationService.sendStudyResearcherDeclined(psr, c);
                }
            }
        }
    }

    private static List<PP_EmailNotificationService.CoordinatorInfo> resolveIfNull(
            StudyRequest__c psr,
            List<PP_EmailNotificationService.CoordinatorInfo> existing) {
        return existing != null
            ? existing
            : PP_EmailNotificationService.resolveCoordinatorInfos(psr.Site_Code__c);
    }

    private static PP_EmailNotificationService.CoordinatorInfo firstOrNull(
            List<PP_EmailNotificationService.CoordinatorInfo> coords) {
        return (coords == null || coords.isEmpty()) ? null : coords[0];
    }

    private static List<StudyRequest__c> queryFullPsrs(Set<Id> ids) {
        return [
            SELECT Id, Name, Study_Name__c, Donors_Requested__c, Client_Deadline__c, Site_Code__c,
                   Sanguine_Status__c, Site_Response_Status__c, Client_Status__c
            FROM StudyRequest__c
            WHERE Id IN :ids
        ];
    }

    private static Boolean statusChanged(StudyRequest__c n, StudyRequest__c o) {
        return (SANGUINE_STATUS_TRIGGERS.contains(n.Sanguine_Status__c)        && n.Sanguine_Status__c      != o.Sanguine_Status__c)
            || (SITE_RESPONSE_STATUS_TRIGGERS.contains(n.Site_Response_Status__c) && n.Site_Response_Status__c != o.Site_Response_Status__c)
            || (CLIENT_STATUS_TRIGGERS.contains(n.Client_Status__c)            && n.Client_Status__c        != o.Client_Status__c);
    }

    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
