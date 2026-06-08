public without sharing class Portal_SupplyRequestEmailHandler implements ITriggerHandler {

    public void afterInsert(List<SObject> newRecords) {
        // EN-07 fires once per new Donor Request — no batching.
        Set<Id> psrIds = new Set<Id>();
        List<SupplyRequest__c> validPdrs = new List<SupplyRequest__c>();
        for (SObject record : newRecords) {
            SupplyRequest__c pdr = (SupplyRequest__c) record;
            if (pdr.ProjectRequest__c == null) continue;
            validPdrs.add(pdr);
            psrIds.add(pdr.ProjectRequest__c);
        }
        if (validPdrs.isEmpty()) return;

        Map<Id, ProjectRequest__c> psrMap = new Map<Id, ProjectRequest__c>([
            SELECT Id, Name, Study_Name__c, Site_Code__c, Client_Deadline__c, Donors_Requested__c
            FROM ProjectRequest__c
            WHERE Id IN :psrIds
        ]);

        Map<Id, List<Portal_EmailNotificationService.CoordinatorInfo>> coordsCache =
            new Map<Id, List<Portal_EmailNotificationService.CoordinatorInfo>>();

        for (SupplyRequest__c pdr : validPdrs) {
            ProjectRequest__c psr = psrMap.get(pdr.ProjectRequest__c);
            if (psr == null) continue;
            // EN-07: site-facing — fan out to every assigned partner coordinator, once per donor
            List<Portal_EmailNotificationService.CoordinatorInfo> coords = resolveCached(coordsCache, psr);
            for (Portal_EmailNotificationService.CoordinatorInfo c : coords) {
                Portal_EmailNotificationService.sendNewDonorsAdded(psr, c);
            }
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        Set<Id> psrIdsNeeded = new Set<Id>();
        // Per-biospecimen status-transition events for Incomplete / Scheduled / Complete
        List<PdrStatusEvent> incompleteEvents = new List<PdrStatusEvent>();
        List<PdrStatusEvent> scheduledEvents  = new List<PdrStatusEvent>();
        List<PdrStatusEvent> completeEvents   = new List<PdrStatusEvent>();

        for (SObject record : newRecords) {
            SupplyRequest__c pdr    = (SupplyRequest__c) record;
            SupplyRequest__c oldPdr = (SupplyRequest__c) oldRecordsMap.get(pdr.Id);

            for (PdrStatusEvent evt : detectStatusTransitions(pdr, oldPdr, 'Incomplete')) {
                incompleteEvents.add(evt);
                if (pdr.ProjectRequest__c != null) {
                    psrIdsNeeded.add(pdr.ProjectRequest__c);
                }
            }
            for (PdrStatusEvent evt : detectStatusTransitions(pdr, oldPdr, 'Scheduled')) {
                scheduledEvents.add(evt);
                if (pdr.ProjectRequest__c != null) {
                    psrIdsNeeded.add(pdr.ProjectRequest__c);
                }
            }
            for (PdrStatusEvent evt : detectStatusTransitions(pdr, oldPdr, 'Complete')) {
                completeEvents.add(evt);
                if (pdr.ProjectRequest__c != null) {
                    psrIdsNeeded.add(pdr.ProjectRequest__c);
                }
            }
        }
        if (incompleteEvents.isEmpty() && scheduledEvents.isEmpty() && completeEvents.isEmpty()) return;

        Map<Id, ProjectRequest__c> psrMap = new Map<Id, ProjectRequest__c>([
            SELECT Id, Name, Study_Name__c, Site_Code__c, Client_Deadline__c, Donors_Requested__c
            FROM ProjectRequest__c
            WHERE Id IN :psrIdsNeeded
        ]);

        Map<Id, List<Portal_EmailNotificationService.CoordinatorInfo>> coordsCache =
            new Map<Id, List<Portal_EmailNotificationService.CoordinatorInfo>>();

        for (PdrStatusEvent evt : incompleteEvents) {
            ProjectRequest__c psr = psrMap.get(evt.pdr.ProjectRequest__c);
            if (psr == null) continue;
            List<Portal_EmailNotificationService.CoordinatorInfo> coords = resolveCached(coordsCache, psr);
            // EN-08: site-facing — fan out to every assigned partner coordinator, once per biospecimen
            for (Portal_EmailNotificationService.CoordinatorInfo c : coords) {
                Portal_EmailNotificationService.sendIncompleteCollectionSite(evt.pdr, psr, c, evt.biospecimenType);
            }
            // EN-15: ops-facing — single recipient, once per biospecimen
            Portal_EmailNotificationService.sendIncompleteCollectionOps(evt.pdr, psr, firstOrNull(coords), evt.biospecimenType);
        }

        for (PdrStatusEvent evt : scheduledEvents) {
            ProjectRequest__c psr = psrMap.get(evt.pdr.ProjectRequest__c);
            if (psr == null) continue;
            List<Portal_EmailNotificationService.CoordinatorInfo> coords = resolveCached(coordsCache, psr);
            // EN-18: ops-facing — single recipient
            Portal_EmailNotificationService.sendCollectionScheduledOps(evt.pdr, psr, firstOrNull(coords), evt.biospecimenType);
        }

        for (PdrStatusEvent evt : completeEvents) {
            ProjectRequest__c psr = psrMap.get(evt.pdr.ProjectRequest__c);
            if (psr == null) continue;
            List<Portal_EmailNotificationService.CoordinatorInfo> coords = resolveCached(coordsCache, psr);
            // EN-19: ops-facing — single recipient
            Portal_EmailNotificationService.sendCollectionCompleteOps(evt.pdr, psr, firstOrNull(coords), evt.biospecimenType);
        }
    }

    private static List<Portal_EmailNotificationService.CoordinatorInfo> resolveCached(
            Map<Id, List<Portal_EmailNotificationService.CoordinatorInfo>> cache,
            ProjectRequest__c psr) {
        if (!cache.containsKey(psr.Id)) {
            cache.put(psr.Id, Portal_EmailNotificationService.resolveCoordinatorInfos(psr.Site_Code__c));
        }
        return cache.get(psr.Id);
    }

    private static Portal_EmailNotificationService.CoordinatorInfo firstOrNull(
            List<Portal_EmailNotificationService.CoordinatorInfo> coords) {
        return (coords == null || coords.isEmpty()) ? null : coords[0];
    }

    @TestVisible
    private static List<PdrStatusEvent> detectStatusTransitions(SupplyRequest__c newPdr,
                                                                  SupplyRequest__c oldPdr,
                                                                  String targetStatus) {
        List<PdrStatusEvent> events = new List<PdrStatusEvent>();
        if (newPdr.Blood_Status__c == targetStatus && oldPdr.Blood_Status__c != targetStatus) {
            events.add(new PdrStatusEvent(newPdr, 'Blood'));
        }
        if (newPdr.Synovial_Fluid_Status__c == targetStatus && oldPdr.Synovial_Fluid_Status__c != targetStatus) {
            events.add(new PdrStatusEvent(newPdr, 'Synovial Fluid'));
        }
        if (newPdr.Skin_Punch_Status__c == targetStatus && oldPdr.Skin_Punch_Status__c != targetStatus) {
            events.add(new PdrStatusEvent(newPdr, 'Skin Punch Biopsy'));
        }
        return events;
    }

    @TestVisible
    private class PdrStatusEvent {
        @TestVisible SupplyRequest__c pdr;
        @TestVisible String biospecimenType;
        PdrStatusEvent(SupplyRequest__c pdr, String biospecimenType) {
            this.pdr = pdr;
            this.biospecimenType = biospecimenType;
        }
    }

    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {}
    public void beforeDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterDelete(Map<Id, SObject> oldRecordsMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
