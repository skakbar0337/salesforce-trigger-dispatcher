@IsTest(seeAllData=false)
private class OpportunityCreateHandlerTest {

    /**
     * @description Verifies CampaignMember responded status update (lead conversion/OCR parts removed).
     */
    @IsTest
    static void test_afterInsert_updateCM_only() {
        TestDataFactory f = new TestDataFactory();

        // Active campaign that matches UTM on Opp
        Campaign activePaid = new Campaign(Name='google_q2', Type='Paid Search', IsActive=true);
        insert activePaid;

        // Lead with matching email; CM to be marked responded
        String email = 'user.convert@test.com';
        Lead lead = new Lead(FirstName='L', LastName='One', Company='LOne Co', Status='Prospect', Email=email);
        insert lead;
        insert new CampaignMember(CampaignId=activePaid.Id, LeadId=lead.Id, Status='Sent');

        // Opportunity ties via SRF_Email__c and UTM_Campaign__c
        Opportunity opp = new Opportunity(Name='Opp Insert Biz', StageName='Prospecting', CloseDate=Date.today().addDays(30));
        opp.SRF_Email__c = email;
        opp.UTM_Campaign__c = activePaid.Name;

        Test.startTest();
        insert opp; // after-insert should mark CM Responded
        Test.stopTest();

        CampaignMember cm = [SELECT Id, Status FROM CampaignMember WHERE LeadId = :lead.Id AND CampaignId = :activePaid.Id LIMIT 1];
        System.assertEquals(OpportunityAttributionHandler.CAMPAIGN_RESPONDED_STATUS, cm.Status, 'CM should be marked Responded');
    }

    /**
     * @description Verifies cohort (BidRecord__c) records are cloned
     *              when an Opportunity is created via Salesforce clone().
     */
    @IsTest
    static void test_afterInsert_clone_cohort_records() {
        Opportunity parentOpp = new Opportunity(
            Name='Parent Opp',
            StageName='Prospecting',
            CloseDate=Date.today().addDays(15)
        );
        insert parentOpp;
    
        BidRecord__c cohort = new BidRecord__c(BidRecord__c = parentOpp.Id);
        insert cohort;
    
        // Use real Apex clone API – this sets getCloneSourceId()
        Opportunity childOpp = parentOpp.clone(false, false, false, false);
        childOpp.Name = 'Child Opp';

        Test.startTest();
        insert childOpp; // after-insert clones cohorts
        Test.stopTest();
    
        List<BidRecord__c> cloned = [
            SELECT Id, BidRecord__c
            FROM BidRecord__c
            WHERE BidRecord__c = :childOpp.Id
        ];
        System.assert(!cloned.isEmpty(), 'Cohort records should be cloned to the new Opportunity');
    }
}