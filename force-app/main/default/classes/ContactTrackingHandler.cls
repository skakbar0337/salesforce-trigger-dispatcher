/**
 * @description
 * Handles associating newly inserted or updated Patient contacts with UTM Campaigns based on the UTM_Campaign__c field. 
 * Ensures the contact is added to the specified campaign only if not already a member.
 * @executionOrder 30 (Related Record Handler)
 */

public with sharing class ContactTrackingHandler implements ITriggerHandler {
    
    private static final String PATIENT = 'Patient';
    private static final String CAMPAIGN_RESPONDED_STATUS = 'Responded';
    private static Boolean firstRun = true;

    /**
     * @param newList List of newly inserted Contact records
     */
    public void afterInsert(List<SObject> newList) {
        if (!firstRun) {
            return;
        }
        handleUtmCampaigns((List<Contact>) newList);
        firstRun = false;
    }

    /**
     * @param newList List of updated Contact records
     * @param oldMap Previous state of Contact records
     */
    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        if (!firstRun) {
            return;
        }
        handleUtmCampaigns((List<Contact>) newList);
        firstRun = false;
    }

    /**
     * Associates patients to UTM campaigns if not already added
     */
    private void handleUtmCampaigns(List<Contact> contacts) {
        Map<Id, Contact> processQueueById = new Map<Id, Contact>();
        Set<String> campaigns = new Set<String>();

        for (Contact c : contacts) {
            if (c.RecordTypeId != null &&
                Schema.SObjectType.Contact.getRecordTypeInfosById().get(c.RecordTypeId).getName() == PATIENT &&
                String.isNotBlank(c.UTM_Campaign__c)) {
                processQueueById.put(c.Id, c);
                campaigns.add(c.UTM_Campaign__c);
                    
                    System.debug('Processing Contact => ' + c.Id + ' | RT=' + 
    Schema.SObjectType.Contact.getRecordTypeInfosById().get(c.RecordTypeId).getName() + 
    ' | UTM=' + c.UTM_Campaign__c);

            }
        }

        if (processQueueById.isEmpty()) {
            return;
        }

        // CRUD check before SOQL on Campaign
        if (!Schema.sObjectType.Campaign.isAccessible()) {
            System.debug(LoggingLevel.WARN, 'No read access to Campaign. Aborting UTM campaign association.');
            return;
        }

        Map<String, Id> campaignIdsByName = new Map<String, Id>();
        for (Campaign cmp : [
            SELECT Id, Name FROM Campaign WHERE Name IN :campaigns
        ]) {
            campaignIdsByName.put(cmp.Name, cmp.Id);
        }

        // CRUD check before SOQL on CampaignMember
        if (!Schema.sObjectType.CampaignMember.isAccessible()) {
            System.debug(LoggingLevel.WARN, 'No read access to CampaignMember. Aborting UTM campaign association.');
            return;
        }

        Map<Id, List<Id>> contactIdsByCampaignId = new Map<Id, List<Id>>();
        for (CampaignMember cm : [
            SELECT CampaignId, ContactId FROM CampaignMember
            WHERE CampaignId IN :campaignIdsByName.values()
        ]) {
            if (!contactIdsByCampaignId.containsKey(cm.CampaignId)) {
                contactIdsByCampaignId.put(cm.CampaignId, new List<Id>());
            }
            contactIdsByCampaignId.get(cm.CampaignId).add(cm.ContactId);
        }

        List<CampaignMember> insertQueue = new List<CampaignMember>();
        for (Id cId : processQueueById.keySet()) {
            Contact c = processQueueById.get(cId);
            Id campaignId = campaignIdsByName.get(c.UTM_Campaign__c);

            if (campaignId != null &&
                (!contactIdsByCampaignId.containsKey(campaignId) ||
                !contactIdsByCampaignId.get(campaignId).contains(cId))) {
                insertQueue.add(new CampaignMember(
                    ContactId = cId,
                    CampaignId = campaignId,
                    Status = CAMPAIGN_RESPONDED_STATUS
                ));
            }
        }

        // CRUD check before DML on CampaignMember
        if (!insertQueue.isEmpty()) {
            if (!Schema.sObjectType.CampaignMember.isCreateable()) {
                System.debug(LoggingLevel.WARN, 'No create access to CampaignMember. Skipping DML.');
                return;
            }
            try {
                insert insertQueue;
            } catch (DmlException e) {
                System.debug('Error while adding Campaign Members via UTM: ' + e.getMessage());
            }
        }
    }
    
    // Empty stub methods to satisfy ITriggerHandler interface
    public void beforeInsert(List<SObject> newList) {
    }
    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
    }
    public void beforeDelete(Map<Id, SObject> oldMap) {
    }
    public void afterDelete(Map<Id, SObject> oldMap) {
    }
    public void afterUndelete(List<SObject> newList) {
    }
}