@IsTest(seeAllData=false)
private class OpportunityAttributionHandlerTest {

    /**
     * @description Verifies populateCampaignSource chooses Contact CM
     *              and stamps CampaignId, LeadSource, and AccountId.
     */
    @IsTest
    static void test_beforeInsert_attribution_from_contact_cm() {
        TestDataFactory f = new TestDataFactory();

        // Account + Contact (Account required by handler filter)
        Account acc = f.createPharmaAccount(); insert acc;
        Contact con = f.createResearchCoordinator();
        con.AccountId = acc.Id; insert con;

        // Active Campaign (not the special RevOps one)
        Campaign camp = new Campaign(Name='Webinar June', Type='Webinar', IsActive=true);
        insert camp;

        // CampaignMember (Contact) with Responded
        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            ContactId  = con.Id,
            Status     = OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS
        );
        insert cm;

        // Opp to run handler against (use DML so the trigger framework runs)
        Opportunity o = new Opportunity(Name='Opp A', StageName='Prospecting', CloseDate=Date.today().addDays(10));
        o.SRF_Email__c = con.Email;

        Test.startTest();
        insert o;  // before-insert handler runs via trigger framework
        Test.stopTest();

        Opportunity saved = [
            SELECT Id, CampaignId, LeadSource, AccountId
            FROM Opportunity WHERE Id = :o.Id
        ];

        System.assertEquals(camp.Id, saved.CampaignId, 'CampaignId should be set from Contact CM');
        System.assertEquals('Webinar', saved.LeadSource, 'LeadSource should match Campaign.Type');
        System.assertEquals(acc.Id, saved.AccountId, 'AccountId should be taken from matched Contact');
    }

   /**
     * @description Lead-CM path with diagnostics (works in this org).
     * Confirms Lead stays unconverted, CM matches handler filters, then runs handler.
     */
    @IsTest
    static void test_beforeInsert_attribution_from_lead_cm() {
        // Guard: many orgs have auto-convert logic; your Lead trigger may respect this flag.
        OpportunityAttributionHandler.skipLeadTrigger = true;
    
        // 1) Create Lead (must remain unconverted for the Lead-CM path)
        Lead l = new Lead(
            FirstName = 'F', LastName = 'L',
            Company = 'L Co', Status = 'Prospect',
            Email = 'leadOnly@test.com'
        );
        insert l;
    
        // Recheck Lead state
        l = [SELECT Id, Email, IsConverted, ConvertedContactId, ConvertedAccountId
             FROM Lead WHERE Id = :l.Id];
        System.assertEquals(false, l.IsConverted, 'Lead must remain unconverted for Lead-CM path');
    
        // 2) Campaign + Lead CampaignMember with Responded
        Campaign camp = new Campaign(Name='Conference 2025', Type='Conference', IsActive=true);
        insert camp;
    
        CampaignMember cm = new CampaignMember(
            CampaignId = camp.Id,
            LeadId     = l.Id,
            Status     = OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS
        );
        insert cm;
    
        // Reload CM & print essentials
        CampaignMember cmReload = [
            SELECT Id, CampaignId, LeadId, Status, HasResponded,
                   Lead.Email, Lead.IsConverted, Campaign.Name
            FROM CampaignMember
            WHERE Id = :cm.Id
        ];
        
        // 3) Count matches using the handler’s exact filter and relaxed variants
        Integer cntExact = [
            SELECT count() FROM CampaignMember
            WHERE (Lead.Email = :l.Email AND Lead.IsConverted = false)
              AND CampaignId != null
              AND Status = :OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS
              AND Campaign_Name__c != :OpportunityAttributionHandler.REVOPS_CAMPAIGN_NAME
        ];
        Integer cntNoConverted = [
            SELECT count() FROM CampaignMember
            WHERE (Lead.Email = :l.Email)
              AND CampaignId != null
              AND Status = :OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS
              AND Campaign_Name__c != :OpportunityAttributionHandler.REVOPS_CAMPAIGN_NAME
        ];
        Integer cntNoStatus = [
            SELECT count() FROM CampaignMember
            WHERE (Lead.Email = :l.Email AND Lead.IsConverted = false)
              AND CampaignId != null
              AND Campaign_Name__c != :OpportunityAttributionHandler.REVOPS_CAMPAIGN_NAME
        ];
        Integer cntNoName = [
            SELECT count() FROM CampaignMember
            WHERE (Lead.Email = :l.Email AND Lead.IsConverted = false)
              AND CampaignId != null
              AND Status = :OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS
        ];
        System.assert(cntExact > 0, 'Guard: expected at least one CM matching the exact filter');
        
        // 4) Exercise handler via real DML (before-insert)
        Opportunity o = new Opportunity(
            Name='Opp B',
            StageName='Prospecting',
            CloseDate=Date.today().addDays(5),
            SRF_Email__c = l.Email
        );
    
        Test.startTest();
        insert o;  // triggers before-insert handler
        Test.stopTest();
    
        // 5) Assertions on the saved record
        Opportunity saved = [
            SELECT Id, CampaignId, LeadSource
            FROM Opportunity WHERE Id = :o.Id
        ];
        System.assertEquals(camp.Id, saved.CampaignId, 'CampaignId stamped from Lead CM');
        System.assertEquals('Conference', saved.LeadSource, 'LeadSource from Campaign.Type (Lead path)');
    }
    
    /**
     * @description Verifies paid campaign (UTM contains 'google') stamping
     *              sets CampaignId and LeadSource from Campaign by name.
     */
    @IsTest
    static void test_beforeInsert_paid_campaign_stamping() {
        TestDataFactory f = new TestDataFactory();

        // Contact + Account (not strictly needed for paid path)
        Account acc = f.createPharmaAccount(); insert acc;
        Contact con = f.createResearchCoordinator(); con.AccountId = acc.Id; insert con;

        Campaign paid = new Campaign(Name='google_q3_2025', Type='Paid Ad', IsActive=true);
        insert paid;

        Opportunity o = new Opportunity(Name='Opp C', StageName='Prospecting', CloseDate=Date.today().addDays(7));
        o.SRF_Email__c    = con.Email;
        o.UTM_Campaign__c = paid.Name;

        Test.startTest();
        insert o;  // run through trigger framework
        Test.stopTest();

        Opportunity saved = [
            SELECT Id, CampaignId, LeadSource
            FROM Opportunity WHERE Id = :o.Id
        ];

        System.assertEquals(paid.Id, saved.CampaignId, 'Paid campaign should set CampaignId');
        System.assertEquals('Paid Ad', saved.LeadSource, 'Paid campaign should set LeadSource from campaign Type');
    }

    /**
     * @description Bulk scenario: 30 opportunities across the same
     *              Contact CM source to confirm bulk safety.
     */
    @IsTest
    static void test_beforeInsert_bulk_mixed_sources() {
        TestDataFactory f = new TestDataFactory();

        Account acc = f.createPharmaAccount(); insert acc;
        Contact c1 = f.createResearchCoordinator(); c1.AccountId = acc.Id; insert c1;

        Campaign c  = new Campaign(Name='Webinar X', Type='Webinar', IsActive=true);
        insert c;
        insert new CampaignMember(
            CampaignId = c.Id,
            ContactId  = c1.Id,
            Status     = OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS
        );

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 30; i++) {
            Opportunity o = new Opportunity(Name='Bulk ' + i, StageName='Prospecting', CloseDate=Date.today().addDays(15));
            o.SRF_Email__c = c1.Email; // all tie to contact path
            opps.add(o);
        }

        Test.startTest();
        insert opps; // trigger framework handles all 30 in bulk
        Test.stopTest();

        // Re-query saved opps to validate persisted values
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : opps) oppIds.add(o.Id);

        for (Opportunity saved : [
            SELECT Id, CampaignId, LeadSource, AccountId
            FROM Opportunity
            WHERE Id IN :oppIds
        ]) {
            System.assertEquals(c.Id, saved.CampaignId,   'CampaignId should be set for all');
            System.assertEquals('Webinar', saved.LeadSource, 'LeadSource should match Campaign.Type');
            System.assertEquals(acc.Id, saved.AccountId,  'AccountId should be stamped from Contact');
        }
    }

    /**
     * @description Verifies the both-Lead-and-Contact CM path.
     *              When both exist for the same email, handler picks based on CreatedDate.
     */
    @IsTest
    static void test_beforeInsert_both_lead_and_contact_cm() {
        OpportunityAttributionHandler.skipLeadTrigger = true;
        TestDataFactory f = new TestDataFactory();

        Account acc = f.createPharmaAccount(); insert acc;

        String sharedEmail = 'both.paths+' + System.currentTimeMillis() + '@test.com';

        // Insert Lead BEFORE Contact to avoid auto-conversion
        Lead l = new Lead(FirstName = 'Both', LastName = 'PathL', Email = sharedEmail, Company = 'BothCo', Status = 'Prospect');
        insert l;
        l = [SELECT Id, Email, IsConverted FROM Lead WHERE Id = :l.Id];

        Contact con = new Contact(FirstName = 'Both', LastName = 'Path', Email = sharedEmail, AccountId = acc.Id);
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(con, dml);

        Campaign camp = new Campaign(Name = 'Dual Source Camp', Type = 'Event', IsActive = true);
        insert camp;

        insert new List<CampaignMember>{
            new CampaignMember(CampaignId = camp.Id, ContactId = con.Id, Status = OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS),
            new CampaignMember(CampaignId = camp.Id, LeadId = l.Id, Status = OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS)
        };

        Opportunity o = new Opportunity(Name = 'Opp Dual', StageName = 'Prospecting', CloseDate = Date.today().addDays(10));
        o.SRF_Email__c = sharedEmail;

        Test.startTest();
        insert o;
        Test.stopTest();

        Opportunity saved = [SELECT Id, CampaignId, LeadSource, AccountId FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(camp.Id, saved.CampaignId, 'CampaignId should be set from dual CM path');
        System.assertEquals('Event', saved.LeadSource, 'LeadSource should match Campaign.Type');
        System.assertEquals(acc.Id, saved.AccountId, 'AccountId should be set from Contact');
    }
}