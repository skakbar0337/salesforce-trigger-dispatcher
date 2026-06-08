public with sharing class ContactCampaignHandler implements ITriggerHandler {

    private static final String RESEARCHER_RT_DEV   = 'Researcher';
    private static final String RESEARCHER_RT_LABEL = 'Scientist';
    private static final String CAMPAIGN_NAME       = 'Revenue Operations Funnel Campaign';
    private static final String CAMPAIGN_STATUS     = 'Responded';

    public void afterInsert(List<SObject> newList) {
        if (newList == null || newList.isEmpty()) return;

        Id researcherRtId;
        Map<String, Schema.RecordTypeInfo> byDev  = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName();
        Map<String, Schema.RecordTypeInfo> byName = Schema.SObjectType.Contact.getRecordTypeInfosByName();

        if (byDev != null && byDev.containsKey(RESEARCHER_RT_DEV)) {
            researcherRtId = byDev.get(RESEARCHER_RT_DEV).getRecordTypeId();
        } else if (byName != null && byName.containsKey(RESEARCHER_RT_LABEL)) {
            researcherRtId = byName.get(RESEARCHER_RT_LABEL).getRecordTypeId();
        }
        if (researcherRtId == null) return;

        List<Contact> researchers = new List<Contact>();
        for (Contact c : (List<Contact>) newList) {
            if (c.RecordTypeId == researcherRtId) {
                researchers.add(c);
            }
        }
        if (researchers.isEmpty()) return;

        if (!Schema.sObjectType.Campaign.isAccessible()) return;

        Campaign revOpsCampaign;
        try {
            revOpsCampaign = [
                SELECT Id
                FROM Campaign
                WHERE Name = :CAMPAIGN_NAME
                  AND IsActive = true
                LIMIT 1
            ];
        } catch (Exception e) {
            return;
        }
        if (revOpsCampaign == null) return;

        Set<Id> targetIds = new Set<Id>();
        for (Contact c : researchers) targetIds.add(c.Id);

        if (!Schema.sObjectType.CampaignMember.isAccessible()) return;

        Set<Id> existing = new Set<Id>();
        for (CampaignMember cm : [
            SELECT ContactId, LeadOrContactId
            FROM CampaignMember
            WHERE CampaignId = :revOpsCampaign.Id
              AND IsDeleted = false
              AND (ContactId IN :targetIds OR LeadOrContactId IN :targetIds)
        ]) {
            if (cm.ContactId != null)       existing.add(cm.ContactId);
            if (cm.LeadOrContactId != null) existing.add(cm.LeadOrContactId);
        }

        List<CampaignMember> toInsert = new List<CampaignMember>();
        for (Contact c : researchers) {
            if (!existing.contains(c.Id)) {
                toInsert.add(new CampaignMember(
                    ContactId  = c.Id,
                    CampaignId = revOpsCampaign.Id,
                    Status     = CAMPAIGN_STATUS
                ));
            }
        }

        if (!toInsert.isEmpty() && Schema.sObjectType.CampaignMember.isCreateable()) {
            try { insert toInsert; } catch (DmlException e) { /* swallow */ }
        }
    }

    public void afterUpdate(List<SObject> n, Map<Id,SObject> o) {}
    public void beforeInsert(List<SObject> n) {}
    public void beforeUpdate(List<SObject> n, Map<Id,SObject> o) {}
    public void beforeDelete(Map<Id,SObject> o) {}
    public void afterDelete(Map<Id,SObject> o) {}
    public void afterUndelete(List<SObject> n) {}
}
