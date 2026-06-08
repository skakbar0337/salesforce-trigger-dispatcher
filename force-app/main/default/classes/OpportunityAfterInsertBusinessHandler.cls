/**
 * @description       : AFTER INSERT business sequence preserving legacy order (post-cleanup):
 * 1) Clone cohort Proposal__c records from the clone source Opportunity,
 * 2) Mark related CampaignMembers as Responded for qualifying UTM campaigns.
 * (Note: lead conversion & OpportunityContactRole creation logic removed as requested.)
 *
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-28
 * @executionOrder    : 55 (Complex Business Logic)
 * @group             : Opportunity Trigger Handlers
 * @group-content     : OpportunityAfterInsertBusinessHandler.cls
 */
public with sharing class OpportunityAfterInsertBusinessHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'OpportunityAfterInsertBusinessHandler';

    public void afterInsert(List<SObject> newRecords) {
        try {
            List<Opportunity> opps = (List<Opportunity>) newRecords;
            cloneCohortRecords(opps);
            updateCampaignMember(opps);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    // --- cloneCohortRecords (unchanged) ---
    private static void cloneCohortRecords(List<Opportunity> newOpp) {
        List<Opportunity> cloneOppList = new List<Opportunity>();
        Set<Id> parentOppIds = new Set<Id>();
        for (Opportunity opp : newOpp) {
            if (opp.getCloneSourceId() != null) {
                cloneOppList.add(opp);
                parentOppIds.add(opp.getCloneSourceId());
            }
        }
        if (parentOppIds.isEmpty()) return;

        Schema.DescribeSObjectResult d = Proposal__c.sObjectType.getDescribe();
        Map<String, Schema.SObjectField> fMap = d.fields.getMap();
        String q = '';
        for (Schema.SObjectField fld : fMap.values()) { q += ',' + fld.getDescribe().getName(); }
        q = q.substring(1);
        String soql = 'SELECT ' + q + ' FROM Proposal__c WHERE Proposal__c IN :parentOppIds ORDER BY Name ASC';

        Map<Id, List<Proposal__c>> cohortsByOpp = new Map<Id, List<Proposal__c>>();
        for (Proposal__c s : Database.query(soql)) {
            if (!cohortsByOpp.containsKey(s.Proposal__c)) cohortsByOpp.put(s.Proposal__c, new List<Proposal__c>());
            cohortsByOpp.get(s.Proposal__c).add(s);
        }

        List<Proposal__c> toInsert = new List<Proposal__c>();
        for (Opportunity opp : cloneOppList) {
            if (cohortsByOpp.containsKey(opp.getCloneSourceId())) {
                for (Proposal__c s : cohortsByOpp.get(opp.getCloneSourceId())) {
                    Proposal__c copy = s.clone();
                    copy.Proposal__c = opp.Id;
                    toInsert.add(copy);
                }
            }
        }
        if (!toInsert.isEmpty()) { Database.insert(toInsert); }
    }

    // --- updateCampaignMember (unchanged) ---
    private static void updateCampaignMember(List<Opportunity> newOpp) {
        Map<String, String> utmByEmail = new Map<String, String>();
        for (Opportunity o : newOpp) {
            if (o.UTM_Campaign__c != null && o.SRF_Email__c != null) {
                utmByEmail.put(o.SRF_Email__c, o.UTM_Campaign__c);
            }
        }
        if (utmByEmail.isEmpty()) return;

        Set<Id> campaignIds = new Set<Id>();
        Set<Id> leadOrContactIds = new Set<Id>();
        for (Campaign c : [SELECT Id FROM Campaign WHERE IsActive = true AND Name IN :utmByEmail.values()]) {
            campaignIds.add(c.Id);
        }
        for (Contact c : [SELECT Id FROM Contact WHERE Email IN :utmByEmail.keySet() AND IsDeleted = false]) {
            leadOrContactIds.add(c.Id);
        }
        for (Lead l : [SELECT Id FROM Lead WHERE Email IN :utmByEmail.keySet() AND IsConverted = false AND IsDeleted = false]) {
            leadOrContactIds.add(l.Id);
        }
        if (campaignIds.isEmpty() || leadOrContactIds.isEmpty()) return;

        Map<Id, CampaignMember> toUpdate = new Map<Id, CampaignMember>();
        for (CampaignMember cm : [
            SELECT Id, Status, HasResponded, FirstRespondedDate
            FROM CampaignMember
            WHERE CampaignId IN :campaignIds
              AND LeadOrContactId IN :leadOrContactIds
              AND Status != :OpportunityCampaignAttributionHandler.CAMPAIGN_RESPONDED_STATUS
              AND IsDeleted = false
        ]) {
            cm.Status = OpportunityCampaignAttributionHandler.CAMPAIGN_RESPONDED_STATUS;
            toUpdate.put(cm.Id, cm);
        }
        if (!toUpdate.isEmpty()) {
            try { Database.update(toUpdate.values(), false); }
            catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, e.getMessage());
            }
        }
    }

    // Unused
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
