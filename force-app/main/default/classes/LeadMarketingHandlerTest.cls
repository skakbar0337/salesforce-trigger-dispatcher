@IsTest
private class LeadMarketingHandlerTest {

    private static TestDataFactory factory = new TestDataFactory();

    @IsTest
    static void testAfterInsert_addsLeadToRevOpsCampaign() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Campaign revOpsCampaign = factory.createCampaign('Revenue Operations Funnel Campaign', true);
            insert revOpsCampaign;

            Lead lead = factory.createLeadForCampaignTest();

            Test.startTest();
            insert lead;
            Test.stopTest();

            List<CampaignMember> members = [
                SELECT Id FROM CampaignMember
                WHERE CampaignId = :revOpsCampaign.Id AND LeadId = :lead.Id
            ];
            System.assertEquals(1, members.size(), 'Lead should be added to RevOps campaign on insert');
        }
    }

    @IsTest
    static void testAfterInsert_skipsDuplicateMember() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Campaign revOpsCampaign = factory.createCampaign('Revenue Operations Funnel Campaign', true);
            insert revOpsCampaign;

            Lead lead = factory.createLeadForCampaignTest();
            insert lead;

            // Trigger already added lead to campaign — calling handler directly should detect existing member and skip
            LeadMarketingHandler handler = new LeadMarketingHandler();
            Test.startTest();
            handler.afterInsert(new List<SObject>{ lead });
            Test.stopTest();

            List<CampaignMember> members = [
                SELECT Id FROM CampaignMember
                WHERE CampaignId = :revOpsCampaign.Id AND LeadId = :lead.Id
            ];
            System.assertEquals(1, members.size(), 'Should not create duplicate campaign member');
        }
    }

    @IsTest
    static void testAfterInsert_noRevOpsCampaign_noError() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead lead = factory.createLeadForCampaignTest();

            Test.startTest();
            insert lead;
            Test.stopTest();

            List<CampaignMember> members = [SELECT Id FROM CampaignMember WHERE LeadId = :lead.Id];
            System.assertEquals(0, members.size(), 'No members should be created without RevOps campaign');
        }
    }

    @IsTest
    static void testAfterUpdate_conversionStampsCampaignOnOpp() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Campaign nonRevOpsCampaign = factory.createCampaign('Test Custom Campaign', false);
            insert nonRevOpsCampaign;

            Lead lead = factory.createLeadForCampaignTest();
            insert lead;

            insert new CampaignMember(LeadId = lead.Id, CampaignId = nonRevOpsCampaign.Id, Status = 'Responded');

            Account acc = new Account(Name = 'Test Convert Account');
            insert acc;

            String convertedStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel;

            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(lead.Id);
            lc.setDoNotCreateOpportunity(false);
            lc.setConvertedStatus(convertedStatus);
            lc.setAccountId(acc.Id);

            Test.startTest();
            Database.LeadConvertResult lcr = Database.convertLead(lc);
            Test.stopTest();

            System.assert(lcr.isSuccess(), 'Lead conversion should succeed');
            Opportunity opp = [SELECT Id, CampaignId FROM Opportunity WHERE Id = :lcr.getOpportunityId()];
            System.assertEquals(nonRevOpsCampaign.Id, opp.CampaignId, 'Opp campaign should be stamped from lead campaign member');
        }
    }

    @IsTest
    static void testAfterUpdate_noConversion_noChange() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead lead = factory.createLeadForCampaignTest();
            insert lead;

            LeadMarketingHandler handler = new LeadMarketingHandler();
            Map<Id, SObject> oldMap = new Map<Id, SObject>{ lead.Id => lead.clone(true) };
            lead.Title = 'Updated Title';

            Test.startTest();
            handler.afterUpdate(new List<SObject>{ lead }, oldMap);
            Test.stopTest();
        }
    }

    @IsTest
    static void testHandlerEmptyInputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            LeadMarketingHandler handler = new LeadMarketingHandler();
            Test.startTest();
            handler.beforeInsert(new List<SObject>());
            handler.beforeUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.beforeDelete(new Map<Id, SObject>());
            handler.afterInsert(new List<SObject>());
            handler.afterUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.afterDelete(new Map<Id, SObject>());
            handler.afterUndelete(new List<SObject>());
            Test.stopTest();
        }
    }
}