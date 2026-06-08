/**
 * @description
 * The LeadConversionHandler handles stamping the converted Contact on
 * related Incidence Checks and assigning the Lead Owner to the converted Opportunity.
 * Author: Refactored by S.M Akbar
 * @executionOrder 40 (Complex Business Logic Handler)
 */
public with sharing class LeadConversionHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'LeadConversionHandler';

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            checkForConversion((List<Lead>) newRecords, (Map<Id, Lead>) oldMap);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private void checkForConversion(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        List<Lead> leadsToProcess = new List<Lead>();
        List<Lead> convertedLeadsWithOpps = new List<Lead>();

        for (Lead l : newLeads) {
            if (l.IsConverted && !oldMap.get(l.Id).IsConverted) {
                leadsToProcess.add(l);
                if (l.ConvertedOpportunityId != null) {
                    convertedLeadsWithOpps.add(l);
                }
            }
        }

        if (!leadsToProcess.isEmpty()) {
            stampContactOnIncidenceCheck(leadsToProcess);
        }

        if (!convertedLeadsWithOpps.isEmpty()) {
            stampLeadOwnerOnOpp(convertedLeadsWithOpps);
        }
    }

    private void stampLeadOwnerOnOpp(List<Lead> leads) {
        if (!Schema.sObjectType.Opportunity.isAccessible() ||
            !Schema.sObjectType.Opportunity.fields.Lead_Owner_At_Conversion__c.isUpdateable()) {
            return;
        }

        Map<Id, Id> leadOwnerIdByOppId = new Map<Id, Id>();
        for (Lead l : leads) {
            if (l.OwnerId != null) {
                leadOwnerIdByOppId.put(l.ConvertedOpportunityId, l.OwnerId);
            }
        }

        List<Opportunity> updateQueue = new List<Opportunity>();
        if (!leadOwnerIdByOppId.isEmpty()) {
            for (Opportunity o : [SELECT Id, Lead_Owner_At_Conversion__c FROM Opportunity WHERE Id IN :leadOwnerIdByOppId.keySet()]) {
                o.Lead_Owner_At_Conversion__c = leadOwnerIdByOppId.get(o.Id);
                updateQueue.add(o);
            }

            if (!updateQueue.isEmpty() && Schema.sObjectType.Opportunity.isUpdateable()) {
                update updateQueue;
            }
        }
    }

    private void stampContactOnIncidenceCheck(List<Lead> convertedLeads) {
        if (!Schema.sObjectType.Incidence_Check__c.isAccessible() ||
            !Schema.sObjectType.Incidence_Check__c.fields.Contact__c.isUpdateable()) {
            return;
        }

        Map<Id, Lead> leadsById = new Map<Id, Lead>(convertedLeads);
        List<Incidence_Check__c> updateQueue = new List<Incidence_Check__c>();

        for (Incidence_Check__c ic : [SELECT Id, Lead__c FROM Incidence_Check__c WHERE Lead__c IN :leadsById.keySet()]) {
            if (leadsById.get(ic.Lead__c).ConvertedContactId != null) {
                ic.Contact__c = leadsById.get(ic.Lead__c).ConvertedContactId;
                updateQueue.add(ic);
            }
        }

        if (!updateQueue.isEmpty() && Schema.sObjectType.Incidence_Check__c.isUpdateable()) {
            try {
                update updateQueue;
            } catch (DmlException e) {
                for (Lead l : convertedLeads) {
                    l.addError('Error while updating Incidence Check: ' + e.getMessage());
                }
            }
        }
    }

    public void beforeInsert(List<SObject> newList) {}
    public void afterInsert(List<SObject> newList) {}
    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newList) {}
}
