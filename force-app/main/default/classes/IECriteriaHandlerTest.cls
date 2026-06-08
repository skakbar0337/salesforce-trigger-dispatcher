@isTest
public class IECriteriaHandlerTest {

    private static Opportunity createTestOpp() {
        Id recordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByName()
            .get('Inventory / Banked Samples').getRecordTypeId();
        return new Opportunity(
            RecordTypeId = recordTypeId,
            Name = 'test',
            StageName = 'Stage 1 - Information Gathering',
            CloseDate = System.today(),
            Sponsor_Type__c = 'Big Pharma',
            SRF_Email__c = 'abc.xyz@abc.com',
            Type = 'Inventory',
            Project_Type__c = 'Home-Based Specimen Collection',
            Order_Type__c = 'Inventory Products',
            Sanguine_Projected_Timeline_no_of_mos__c = 5,
            UTM_Campaign__c = 'test_campaign_xyz'
        );
    }

    @isTest
    private static void testOldCheckForApproval() {
        Criterion__c approved = new Criterion__c(
            Status__c = 'Approved', Approved_By__c = null, Approved_On__c = null
        );
        Criterion__c unapproved = new Criterion__c(
            Status__c = 'New',
            Approved_By__c = UserInfo.getUserId(),
            Approved_On__c = Date.today()
        );
        List<Criterion__c> criteria = new List<Criterion__c>{ approved, unapproved };

        Test.startTest();
        IECriteriaHandler.checkForApproval(criteria);
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), approved.Approved_By__c, 'Should stamp approval');
        System.assertEquals(Date.today(), approved.Approved_On__c, 'Should stamp approval date');
        System.assertEquals(null, unapproved.Approved_By__c, 'Should clear approval');
        System.assertEquals(null, unapproved.Approved_On__c, 'Should clear approval date');
    }

    @isTest
    private static void testOldFormatCriteria() {
        List<Criterion__c> criteria = new List<Criterion__c>{
            new Criterion__c(
                Criterion_Type__c = 'Inclusion', Is_Custom__c = true,
                Attribute_Type__c = 'Diagnosis', Criterion_Details__c = 'Diag inclusion'
            ),
            new Criterion__c(
                Criterion_Type__c = 'Inclusion', Is_Custom__c = false,
                Attribute_Type__c = 'Other', Criterion_Details__c = 'Standard inclusion'
            ),
            new Criterion__c(
                Criterion_Type__c = 'Inclusion', Is_Custom__c = true,
                Attribute_Type__c = 'Other', Criterion_Details__c = 'Custom inclusion'
            ),
            new Criterion__c(
                Criterion_Type__c = 'Exclusion', Is_Custom__c = true,
                Attribute_Type__c = 'Diagnosis', Criterion_Details__c = 'Diag exclusion'
            ),
            new Criterion__c(
                Criterion_Type__c = 'Exclusion', Is_Custom__c = true,
                Attribute_Type__c = 'Other', Criterion_Details__c = 'Custom exclusion'
            ),
            new Criterion__c(
                Criterion_Type__c = 'Exclusion', Is_Custom__c = false,
                Attribute_Type__c = 'Other', Criterion_Details__c = 'Standard exclusion'
            )
        };

        Test.startTest();
        String result = IECriteriaHandler.formatCriteria(criteria);
        Test.stopTest();

        System.assert(result.contains('Inclusion'), 'Should contain Inclusion header');
        System.assert(result.contains('Exclusion'), 'Should contain Exclusion header');
        System.assert(result.contains('Diag inclusion'), 'Should contain diagnosis inclusion');
    }

    @isTest
    private static void testOldAggregateOnCohort() {
        CohortIEOrchestrator.disableOrchestration();
        CohortCriteriaHandler.disableDefaultCriteriaCreation();

        Opportunity opp = createTestOpp();
        insert opp;

        Proposal__c cohort = new Proposal__c(Proposal__c = opp.Id);
        insert cohort;

        Criterion__c criterion = new Criterion__c(
            Cohort__c = cohort.Id, Is_Custom__c = true, Status__c = 'New',
            Criterion_Type__c = 'Inclusion', Attribute_Type__c = 'Diagnoses',
            Criterion_Details__c = 'Test inclusion criterion'
        );
        insert criterion;

        Test.startTest();
        IECriteriaHandler.aggregateOnCohort(new List<Criterion__c>{ criterion });
        Test.stopTest();

        Proposal__c updated = [SELECT I_E_Criteria__c FROM Proposal__c WHERE Id = :cohort.Id];
        System.assertNotEquals(null, updated.I_E_Criteria__c, 'Should populate I_E_Criteria__c');

        CohortCriteriaHandler.enableDefaultCriteriaCreation();
        CohortIEOrchestrator.enableOrchestration();
    }

    @isTest
    private static void testApprovalStamping() {
        // Disable orchestrator to isolate test
        CohortIEOrchestrator.disableOrchestration();
        CohortCriteriaHandler.disableDefaultCriteriaCreation();

        Opportunity opp = createTestOpp();
        insert opp;

        Proposal__c cohort = new Proposal__c(Proposal__c = opp.Id);
        insert cohort;

        // Insert a custom criterion directly
        Criterion__c criterion = new Criterion__c(
            Cohort__c = cohort.Id,
            Is_Custom__c = true,
            Status__c = 'New',
            Criterion_Type__c = 'Exclusion',
            Attribute_Type__c = 'Age Range',
            Criterion_Details__c = 'exl criterion 1'
        );
        insert criterion;

        // Update status to Approved
        criterion.Status__c = 'Approved';
        update criterion;

        Criterion__c approvedCriterion = [
            SELECT Approved_By__c, Approved_On__c
            FROM Criterion__c
            WHERE Id = :criterion.Id
        ];

        System.assertEquals(Date.today(), approvedCriterion.Approved_On__c);
        System.assertEquals(UserInfo.getUserId(), approvedCriterion.Approved_By__c);

        CohortCriteriaHandler.enableDefaultCriteriaCreation();
        CohortIEOrchestrator.enableOrchestration();
    }
}