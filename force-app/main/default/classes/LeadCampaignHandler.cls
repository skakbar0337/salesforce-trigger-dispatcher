/**
 * @description
 * The LeadCampaignHandler manages automatic campaign member creation for new leads and updates
 * the Opportunity's campaign upon lead conversion.
 * Author: Refactored by S.M Akbar
 * @executionOrder 20 (Field Defaults & Updates Handler)
 */
public with sharing class LeadCampaignHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'LeadCampaignHandler';
    private static final String REVOPS_CAMPAIGN_NAME = 'Revenue Operations Funnel Campaign';
    private static final String CAMPAIGN_RESPONDED_STATUS = 'Responded';

    public void afterInsert(List<SObject> newRecords) {
        try {
            addToCampaign((List<Lead>) newRecords);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            updateCampaignOnOpportunity((List<Lead>) newRecords, (Map<Id, Lead>) oldMap);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private void addToCampaign(List<Lead> leads) {
        Map<Id, Lead> leadsById = new Map<Id, Lead>(leads);
        Campaign revOpsCampaign;

        if (Schema.sObjectType.Campaign.isAccessible()) {
            for (Campaign c : [SELECT Id FROM Campaign WHERE Name = :REVOPS_CAMPAIGN_NAME AND IsActive = true LIMIT 1]) {
                revOpsCampaign = c;
            }
        }

        Set<Id> existingMemberIds = new Set<Id>();
        if (revOpsCampaign != null && Schema.sObjectType.CampaignMember.isAccessible()) {
            for (CampaignMember cm : [
                SELECT LeadId, LeadOrContactId FROM CampaignMember
                WHERE CampaignId = :revOpsCampaign.Id
                AND IsDeleted = false
                ORDER BY CreatedDate DESC
                LIMIT 40000
            ]) {
                if (cm.LeadId != null) existingMemberIds.add(cm.LeadId);
                if (cm.LeadOrContactId != null) existingMemberIds.add(cm.LeadOrContactId);
            }

            List<CampaignMember> newMembers = new List<CampaignMember>();
            for (Lead l : leads) {
                if (!existingMemberIds.contains(l.Id)) {
                    newMembers.add(new CampaignMember(
                        LeadId     = l.Id,
                        CampaignId = revOpsCampaign.Id,
                        Status     = CAMPAIGN_RESPONDED_STATUS
                    ));
                }
            }

            if (!newMembers.isEmpty() && Schema.sObjectType.CampaignMember.isCreateable()) {
                try {
                    insert newMembers;
                } catch (DmlException e) {
                    for (Lead l : leads) {
                        l.addError('Error occurred while adding lead to the RevOps campaign. Please notify an admin with this error: ' + e.getMessage());
                    }
                }
            }
        }
    }

    private void updateCampaignOnOpportunity(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        Set<Id> opportunityIDs = new Set<Id>();
        List<Lead> leadsToProcess = new List<Lead>();

        for (Lead l : newLeads) {
            if (l.isConverted && oldMap.get(l.Id).isConverted != l.IsConverted && l.ConvertedOpportunityId != null) {
                opportunityIDs.add(l.ConvertedOpportunityId);
                leadsToProcess.add(l);
            }
        }

        Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>();

        if (!leadsToProcess.isEmpty()
            && Schema.sObjectType.Lead.isAccessible()
            && Schema.sObjectType.CampaignMember.isAccessible()
            && Schema.sObjectType.Opportunity.isUpdateable()) {

            for (Lead l : [SELECT Id, ConvertedOpportunityId,
                          (SELECT CampaignId FROM CampaignMembers
                           WHERE Status = :CAMPAIGN_RESPONDED_STATUS
                           AND Campaign_Name__c != :REVOPS_CAMPAIGN_NAME
                           ORDER BY CreatedDate DESC LIMIT 1)
                          FROM Lead
                          WHERE Id IN :leadsToProcess]) {

                if (!l.CampaignMembers.isEmpty()) {
                    opportunityMap.put(
                        l.ConvertedOpportunityId,
                        new Opportunity(Id = l.ConvertedOpportunityId, CampaignId = l.CampaignMembers[0].CampaignId)
                    );
                }
            }

            if (!opportunityMap.isEmpty()) {
                update opportunityMap.values();
            }
        }
    }

    public void beforeInsert(List<SObject> newList) {}
    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newList) {}
}
