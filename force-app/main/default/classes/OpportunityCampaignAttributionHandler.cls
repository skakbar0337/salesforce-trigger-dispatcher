/**
 * @description       : Populates Primary Campaign, Lead Source, and (when possible) AccountId from CampaignMember/Contact,
 * and handles paid campaign attribution via UTM Campaign (e.g., "google"). Exposes cross-handler state:
 *   - public static Boolean skipLeadTrigger
 *   - public static Map<String, CampaignMember> emailCampaignMap
 * Preserves legacy behavior from OpportunityTriggerHelper.doBeforeInsert() and checkPaidCampaignAttribution().
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-28
 * @executionOrder    : 30 (Field Defaults & Updates)
 * @group             : Opportunity Trigger Handlers
 * @group-content     : OpportunityCampaignAttributionHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - Field‑selective, filtered SOQL; no SOQL/DML in loops; bulk-safe for 200+ records.
 * - Uses defensive lookups and maps; no hardcoded IDs.
 * - Updates only the in-flight Trigger.new records; no side-effect DML here.
 * - Methods < 100 lines, meaningful names, single-responsibility.
 */


public with sharing class OpportunityCampaignAttributionHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'OpportunityCampaignAttributionHandler';

    // === Cross-handler shared state (replaces OpportunityLib) ===
    public  static Boolean skipLeadTrigger = false;
    public  static Map<String, CampaignMember> emailCampaignMap = new Map<String, CampaignMember>();

    // === Constants used by attribution logic ===
    public static final String CAMPAIGN_RESPONDED_STATUS = 'Responded';
    public static final String REVOPS_CAMPAIGN_NAME      = 'Revenue Operations Funnel Campaign';
    public static final String UTM_GOOGLE                = 'google';

    public void beforeInsert(List<SObject> newRecords) {
        try {
            List<Opportunity> opps = (List<Opportunity>) newRecords;
            populateCampaignSource(opps);
            checkPaidCampaignAttribution(opps);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private static void populateCampaignSource(List<Opportunity> newOpp) {
        Set<String> emailIds = new Set<String>();
        List<Opportunity> oppToProcess = new List<Opportunity>();
        Id userId = UserInfo.getUserId();
        if (UserInfo.getUserId() == userId) {
            for (Opportunity opp : newOpp) {
                if (opp.SRF_Email__c != null) {
                    emailIds.add(opp.SRF_Email__c);
                    oppToProcess.add(opp);
                }
            }
        }
        if (emailIds.isEmpty()) return;

        Map<String, Contact> contactByEmail = new Map<String, Contact>();
        for (Contact c : [
            SELECT Id, Name, Email, LeadSource, AccountId
            FROM Contact
            WHERE Email IN :emailIds AND AccountId != null AND Email != null
            ORDER BY CreatedDate DESC
        ]) {
            if (!contactByEmail.containsKey(c.Email)) {
                contactByEmail.put(c.Email, c);
            }
        }

        Map<String, CampaignMember> leadCmByEmail = new Map<String, CampaignMember>();
        Map<String, CampaignMember> conCmByEmail  = new Map<String, CampaignMember>();
        for (CampaignMember cm : [
            SELECT Id, CampaignId, LeadId, Lead.Email, Lead.LeadSource, Lead.CreatedDate,
                   Contact.LeadSource, ContactId, Contact.Email, Contact.AccountId, Contact.CreatedDate,
                   Status, Campaign.Type
            FROM CampaignMember
            WHERE ((Lead.Email IN :emailIds AND Lead.IsConverted = false) OR Contact.Email IN :emailIds)
              AND CampaignId != null
              AND Status = :CAMPAIGN_RESPONDED_STATUS
              AND Campaign_Name__c != :REVOPS_CAMPAIGN_NAME
            ORDER BY Lead.CreatedDate DESC, Contact.CreatedDate DESC
        ]) {
            if (cm.LeadId != null && cm.Lead.Email != null && !leadCmByEmail.containsKey(cm.Lead.Email)) {
                leadCmByEmail.put(cm.Lead.Email, cm);
            }
            if (cm.ContactId != null && cm.Contact.Email != null && !conCmByEmail.containsKey(cm.Contact.Email)) {
                conCmByEmail.put(cm.Contact.Email, cm);
            }
        }

        for (Opportunity opp : oppToProcess) {
            String key = opp.SRF_Email__c;
            Boolean hasLead = leadCmByEmail.containsKey(key);
            Boolean hasCon  = conCmByEmail.containsKey(key);

            if (hasLead && !hasCon) {
                CampaignMember cm = leadCmByEmail.get(key);
                opp.CampaignId = cm.CampaignId;
                opp.LeadSource = cm.Campaign.Type;
                emailCampaignMap.put(key, cm);
                if (contactByEmail.containsKey(key) && contactByEmail.get(key).AccountId != null) {
                    opp.AccountId = contactByEmail.get(key).AccountId;
                }
            } else if (!hasLead && hasCon) {
                CampaignMember cm = conCmByEmail.get(key);
                opp.CampaignId = cm.CampaignId;
                opp.LeadSource = cm.Campaign.Type;
                if (cm.Contact != null) opp.AccountId = cm.Contact.AccountId;
                emailCampaignMap.put(key, cm);
            } else if (hasLead && hasCon) {
                DateTime leadCreated    = leadCmByEmail.get(key).Lead.CreatedDate;
                DateTime contactCreated = conCmByEmail.get(key).Contact.CreatedDate;
                CampaignMember chosen   = (leadCreated >= contactCreated) ? leadCmByEmail.get(key) : conCmByEmail.get(key);
                opp.CampaignId = chosen.CampaignId;
                opp.LeadSource = chosen.Campaign.Type;
                if (conCmByEmail.get(key).Contact != null) {
                    opp.AccountId = conCmByEmail.get(key).Contact.AccountId;
                }
                emailCampaignMap.put(key, chosen);
            } else if (!hasLead && !hasCon && contactByEmail.containsKey(key)) {
                Contact c = contactByEmail.get(key);
                opp.LeadSource = c.LeadSource;
                opp.AccountId = c.AccountId;
            }
        }
    }

    private static void checkPaidCampaignAttribution(List<Opportunity> opps) {
        List<Opportunity> paidOpps = new List<Opportunity>();
        Set<String> campaignNames = new Set<String>();
        for (Opportunity o : opps) {
            if (o.UTM_Campaign__c != null && o.UTM_Campaign__c.contains(UTM_GOOGLE)) {
                paidOpps.add(o);
                campaignNames.add(o.UTM_Campaign__c);
            }
        }
        if (campaignNames.isEmpty()) return;

        Map<String, Campaign> campaignsByName = new Map<String, Campaign>();
        for (Campaign c : [SELECT Id, Name, Type FROM Campaign WHERE Name IN :campaignNames AND IsActive = true]) {
            campaignsByName.put(c.Name, c);
        }
        if (campaignsByName.isEmpty()) return;

        for (Opportunity o : paidOpps) {
            String utm = o.UTM_Campaign__c;
            if (campaignsByName.containsKey(utm)) {
                o.CampaignId = campaignsByName.get(utm).Id;
                o.LeadSource = campaignsByName.get(utm).Type;
            }
        }
    }

    // Unused
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
