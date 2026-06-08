@IsTest
private class LeadConversionHandlerTest {

    private static TestDataFactory factory = new TestDataFactory();

    @IsTest
    static void testAfterUpdate_stampContactOnIncidenceCheck() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead lead = factory.createLeadForConversionTest(UserInfo.getUserId());
            insert lead;

            Id icRecordTypeId = Schema.SObjectType.Incidence_Check__c
                .getRecordTypeInfosByName()
                .get('Donor Recruitment Inquiry')
                .getRecordTypeId();

            List<Incidence_Check__c> checks = factory.createIncidenceChecks(1, lead.Id, null, icRecordTypeId);

            Account acc = new Account(Name = 'Test Conversion Account');
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

            Incidence_Check__c updatedIc = [SELECT Id, Contact__c FROM Incidence_Check__c WHERE Id = :checks[0].Id];
            System.assertEquals(lcr.getContactId(), updatedIc.Contact__c, 'Incidence Check Contact should be stamped with converted contact');
        }
    }

    @IsTest
    static void testAfterUpdate_stampLeadOwnerOnOpp() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead lead = factory.createLeadForConversionTest(UserInfo.getUserId());
            insert lead;

            Account acc = new Account(Name = 'Test Owner Stamp Account');
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
            Opportunity opp = [SELECT Id, Lead_Owner_At_Conversion__c FROM Opportunity WHERE Id = :lcr.getOpportunityId()];
            System.assertEquals(UserInfo.getUserId(), opp.Lead_Owner_At_Conversion__c, 'Opp Lead_Owner_At_Conversion__c should be stamped');
        }
    }

    @IsTest
    static void testAfterUpdate_notConverted_noProcessing() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead lead = factory.createLeadForConversionTest(UserInfo.getUserId());
            insert lead;

            LeadConversionHandler handler = new LeadConversionHandler();
            Map<Id, SObject> oldMap = new Map<Id, SObject>{ lead.Id => lead.clone(true) };
            lead.Title = 'Updated';

            Test.startTest();
            handler.afterUpdate(new List<SObject>{ lead }, oldMap);
            Test.stopTest();
        }
    }

    @IsTest
    static void testHandlerEmptyInputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            LeadConversionHandler handler = new LeadConversionHandler();
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