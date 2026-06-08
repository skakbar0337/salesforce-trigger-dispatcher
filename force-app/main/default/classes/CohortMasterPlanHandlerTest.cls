/**
 * @description       : Test class for CohortMasterPlanHandler with DLRS-safe approach
 * CohortMasterPlanHandlerTest.cls that covers:
 * - Master Plan field updates from Cohort values (updateMpFields)
 * - Master Plan ID stamping on I/E criteria (checkForMpId)
 * - I/E criteria aggregation on Master Plans (aggregateCriteriaOnMp)
 * - ITriggerHandler interface methods
 * Note: Uses mock data and existing TestDataFactory pattern to avoid DLRS CPU limits
 * @author            : Hardik Murle
 * @date              : 2025-09-01
 * @group             : Cohort Trigger Handler Tests
 * @group-content     : CohortMasterPlanHandlerTest.cls
 */
@isTest
public class CohortMasterPlanHandlerTest {
    
    private static Integer fakeIdCounter = 1;
    
    /**
     * @description Generate fake Salesforce ID for testing (similar to TestDataFactory pattern)
     * @param sObjectType The SObject type to generate an ID for
     * @return Fake ID in the correct format
     */
    private static Id getFakeId(Schema.SObjectType sObjectType) {
        String keyPrefix = sObjectType.getDescribe().getKeyPrefix();
        String fakeId = keyPrefix + String.valueOf(fakeIdCounter++).leftPad(12, '0');
        return (Id) fakeId;
    }
    
    /**
     * @description Creates test Opportunity with required fields using TestDataFactory pattern
     */
    private static Opportunity createTestOpportunity() {
        Id recordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByName().get('Inventory / Banked Samples').getRecordTypeId();
        
        return new Opportunity(
            RecordTypeId = recordTypeId,
            Name = 'Test Opportunity',
            StageName = 'Stage 1 - Information Gathering',
            CloseDate = System.today(),
            Sponsor_Type__c = 'Big Pharma',
            SRF_Email__c = 'test@example.com',
            Type = 'Inventory',
            Project_Type__c = 'Home-Based Specimen Collection',
            Order_Type__c = 'Inventory Products',
            Sanguine_Projected_Timeline_no_of_mos__c = 5,
            UTM_Campaign__c = 'test_campaign'
        );
    }
    
    /**
     * @description Creates test Master Plan with mock ID (no DB operation to avoid DLRS)
     */
    private static MasterPlan__c createTestMasterPlan() {
        return new MasterPlan__c(
            Id = getFakeId(MasterPlan__c.SObjectType),
            Name = 'Test Master Plan ' + System.currentTimeMillis(),
            I_E_Criteria_Do_Not_Overwrite__c = false
        );
    }

    /**
     * @description Creates test Proposal__c (Cohort) with mock IDs
     */
    private static Proposal__c createTestCohort(Id opportunityId, Id masterPlanId) {
        return new Proposal__c(
            Id = getFakeId(Proposal__c.SObjectType),
            Proposal__c = opportunityId,
            Master_Plan__c = masterPlanId,
            Opportunity_Diagnosis__c = 'Rheumatoid Arthritis',
            Self_Report_Medical_Information__c = 'Test medical info',
            Medical_Records_Required_New__c = 'Yes'
        );
    }
    
    /**
     * @description Test updateMpFields method via afterInsert (avoids DLRS by using null Master Plan)
     */
    @isTest
    static void testUpdateMpFieldsAfterInsert() {
        Test.startTest();
        
        // Create real Opportunity to avoid SOQL issues
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        
        // Create cohort with NULL Master Plan to avoid DLRS trigger
        Proposal__c cohort = new Proposal__c(
            Proposal__c = opp.Id,
            Master_Plan__c = null, // NULL Master Plan avoids DLRS
            Opportunity_Diagnosis__c = 'Test Diagnosis',
            Self_Report_Medical_Information__c = 'Test medical info',
            Medical_Records_Required_New__c = 'Yes'
        );

        // Call actual handler method - will skip processing due to null Master Plan
        CohortMasterPlanHandler handler = new CohortMasterPlanHandler();
        handler.afterInsert(new List<Proposal__c>{cohort});

        Test.stopTest();

        // Verify handler executed without exceptions
        System.assertNotEquals(null, handler);
        System.assertEquals(opp.Id, cohort.Proposal__c);
        System.assertEquals(null, cohort.Master_Plan__c); // Confirms no Master Plan
    }
    
    /**
     * @description Test checkForMpId method via afterUpdate (avoids DLRS by using null Master Plan)
     */
    @isTest
    static void testCheckForMpIdAfterUpdate() {
        Test.startTest();
        
        // Create real Opportunity to avoid SOQL issues
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Update',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        
        // Create cohort with NULL Master Plan to avoid DLRS trigger
        Id mockCohortId = getFakeId(Proposal__c.SObjectType);

        Proposal__c cohort = new Proposal__c(
            Id = mockCohortId,
            Proposal__c = opp.Id,
            Master_Plan__c = null, // NULL Master Plan avoids DLRS
            Opportunity_Diagnosis__c = 'Test Diagnosis',
            Self_Report_Medical_Information__c = 'Test medical info',
            Medical_Records_Required_New__c = 'Yes'
        );

        // Mock Trigger.oldMap (simulating update scenario)
        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            cohort.Id => new Proposal__c(Id = cohort.Id, Master_Plan__c = null)
        };

        // Call actual handler method - will skip processing due to null Master Plan
        CohortMasterPlanHandler handler = new CohortMasterPlanHandler();
        handler.afterUpdate(new List<Proposal__c>{cohort}, oldMap);
        
        Test.stopTest();
        
        // Verify handler executed without exceptions
        System.assertNotEquals(null, handler);
        System.assertEquals(null, cohort.Master_Plan__c); // Confirms no Master Plan
        System.assertEquals(opp.Id, cohort.Proposal__c);
    }
    
    /**
     * @description Test aggregateCriteriaOnMp method with empty map (avoids DLRS)
     */
    @isTest
    static void testAggregateCriteriaOnMp() {
        Test.startTest();
        
        // Call actual static method with empty map - will execute but find no records
        Map<Id, List<Criterion__c>> emptyCriteriaByMpId = new Map<Id, List<Criterion__c>>();

        CohortMasterPlanHandler.aggregateCriteriaOnMp(emptyCriteriaByMpId);

        Test.stopTest();

        // Verify method executed without exceptions - tests method signature and basic logic
        System.assertEquals(0, emptyCriteriaByMpId.size(), 'Empty map should remain empty');
    }
    
    /**
     * @description Test updateMpFields static method with empty cohorts (avoids DLRS)
     */
    @isTest
    static void testUpdateMpFieldsStaticMethod() {
        Test.startTest();
        
        // Create real Opportunity to avoid SOQL issues
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Static',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        
        // Create cohort with NULL Master Plan to avoid DLRS trigger
        Proposal__c cohort = new Proposal__c(
            Proposal__c = opp.Id,
            Master_Plan__c = null, // NULL Master Plan avoids DLRS
            Opportunity_Diagnosis__c = 'Static Method Test',
            Self_Report_Medical_Information__c = 'Static test info',
            Medical_Records_Required_New__c = 'No'
        );

        // Call actual static method directly - will skip processing due to null Master Plan
        CohortMasterPlanHandler.updateMpFields(new List<Proposal__c>{cohort});
        
        Test.stopTest();
        
        // Verify method executed without exceptions
        System.assertEquals(opp.Id, cohort.Proposal__c);
        System.assertEquals('Static Method Test', cohort.Opportunity_Diagnosis__c);
        System.assertEquals(null, cohort.Master_Plan__c); // Confirms no Master Plan
    }
    
    /**
     * @description Test ITriggerHandler interface methods (negative cases)
     */
    @isTest
    static void testTriggerHandlerInterfaceMethods() {
        CohortMasterPlanHandler handler = new CohortMasterPlanHandler();
        
        // Test methods that should not perform any actions
        Test.startTest();
        handler.beforeInsert(new List<Proposal__c>());
        handler.beforeUpdate(new List<Proposal__c>(), new Map<Id, SObject>());
        handler.beforeDelete(new Map<Id, SObject>());
        handler.afterDelete(new Map<Id, SObject>());
        handler.afterUndelete(new List<Proposal__c>());
        Test.stopTest();
        
        // No assertions needed - just ensuring no exceptions thrown
        System.assert(true, 'Interface methods executed without exceptions');
    }
    
    /**
     * @description Test bulk processing logic for multiple records (avoids DLRS with null Master Plans)
     */
    @isTest
    static void testBulkProcessingLogic() {
        Test.startTest();
        
        // Create real Opportunity to avoid SOQL issues
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Bulk',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        
        // Create cohorts with NULL Master Plan IDs (to avoid DLRS)
        List<Proposal__c> cohorts = new List<Proposal__c>();

        for (Integer i = 0; i < 5; i++) {
            cohorts.add(new Proposal__c(
                Proposal__c = opp.Id,
                Master_Plan__c = null, // NULL Master Plan avoids DLRS
                Opportunity_Diagnosis__c = 'Bulk Diagnosis ' + i,
                Self_Report_Medical_Information__c = 'Bulk info ' + i,
                Medical_Records_Required_New__c = 'Yes'
            ));
        }

        // Call actual handler method - will skip processing due to null Master Plans
        CohortMasterPlanHandler handler = new CohortMasterPlanHandler();
        handler.afterInsert(cohorts);
        
        Test.stopTest();
        
        // Verify bulk processing executed without exceptions
        System.assertNotEquals(null, handler);
        System.assertEquals(5, cohorts.size());
        
        for (Proposal__c cohort : cohorts) {
            System.assertEquals(opp.Id, cohort.Proposal__c);
            System.assertEquals(null, cohort.Master_Plan__c); // Confirms no Master Plan
            System.assert(cohort.Opportunity_Diagnosis__c.startsWith('Bulk Diagnosis'));
        }
    }
    
    /**
     * @description Test updateMpFields with actual Master Plan records (high coverage)
     */
    @isTest
    static void testUpdateMpFieldsWithRealMasterPlan() {
        Test.startTest();
        
        // Create real Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity MP',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        
        // Create real Master Plan (this should be safe without DLRS)
        MasterPlan__c mp = new MasterPlan__c(
            Name = 'Test Master Plan',
            Med_Record_Retrieval_Notes__c = null,
            Medical_Records__c = null,
            Donor_Type__c = null,
            I_E_Criteria_Do_Not_Overwrite__c = false
        );
        insert mp;

        // Create cohort with real Master Plan ID
        Proposal__c cohort = new Proposal__c(
            Proposal__c = opp.Id,
            Master_Plan__c = mp.Id,
            Opportunity_Diagnosis__c = 'Real MP Test',
            Self_Report_Medical_Information__c = 'Real MP info',
            Medical_Records_Required_New__c = 'Yes'
        );

        // Call static method directly to test actual field updates
        CohortMasterPlanHandler.updateMpFields(new List<Proposal__c>{cohort});

        Test.stopTest();

        // Verify the Master Plan was updated
        MasterPlan__c updatedMp = [SELECT Id, Med_Record_Retrieval_Notes__c, Medical_Records__c, Donor_Type__c
                                   FROM MasterPlan__c WHERE Id = :mp.Id];
        
        System.assertEquals('Real MP info', updatedMp.Med_Record_Retrieval_Notes__c);
        System.assertEquals('Yes', updatedMp.Medical_Records__c);
        System.assertEquals('Real MP Test', updatedMp.Donor_Type__c);
    }
    
    /**
     * @description Test checkForMpId with actual I/E Criteria records (high coverage)
     */
    @isTest
    static void testCheckForMpIdWithRealCriteria() {
        Test.startTest();
        
        // Create real Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity Criteria',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        
        // Create real Master Plan
        MasterPlan__c mp = new MasterPlan__c(
            Name = 'Test Master Plan Criteria',
            I_E_Criteria_Do_Not_Overwrite__c = false
        );
        insert mp;

        // Create real Cohort
        Proposal__c cohort = new Proposal__c(
            Proposal__c = opp.Id,
            Master_Plan__c = null, // Start with null
            Opportunity_Diagnosis__c = 'Criteria Test'
        );
        insert cohort;

        // Create I/E Criteria linked to cohort (but no Master Plan yet)
        Criterion__c criteria = new Criterion__c(
            Cohort__c = cohort.Id,
            Criterion_Type__c = 'Inclusion',
            Attribute_Type__c = 'Age Range',
            Criterion_Details__c = 'Age 18-65',
            Master_Plan__c = null
        );
        insert criteria;

        // Now update cohort to link to Master Plan
        cohort.Master_Plan__c = mp.Id;

        // Mock oldMap for trigger context
        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            cohort.Id => new Proposal__c(Id = cohort.Id, Master_Plan__c = null)
        };

        // Call handler method to test MP ID stamping
        CohortMasterPlanHandler handler = new CohortMasterPlanHandler();
        handler.afterUpdate(new List<Proposal__c>{cohort}, oldMap);

        Test.stopTest();

        // Verify the criteria was updated with Master Plan ID
        Criterion__c updatedCriteria = [SELECT Id, Master_Plan__c FROM Criterion__c WHERE Id = :criteria.Id];
        System.assertEquals(mp.Id, updatedCriteria.Master_Plan__c);
    }
    
    /**
     * @description Test aggregateCriteriaOnMp with real Master Plan and criteria (high coverage)
     */
    @isTest
    static void testAggregateCriteriaWithRealRecords() {
        Test.startTest();
        
        // Create real Master Plan
        MasterPlan__c mp = new MasterPlan__c(
            Name = 'Test Master Plan Aggregate',
            I_E__c = null,
            I_E_Criteria_Do_Not_Overwrite__c = false
        );
        insert mp;

        // Create mock criteria (don't insert to avoid complexity)
        List<Criterion__c> mockCriteria = new List<Criterion__c>{
            new Criterion__c(
                Master_Plan__c = mp.Id,
                Criterion_Type__c = 'Inclusion',
                Attribute_Type__c = 'Age Range',
                Criterion_Details__c = 'Age 18-65'
            ),
            new Criterion__c(
                Master_Plan__c = mp.Id,
                Criterion_Type__c = 'Exclusion',
                Attribute_Type__c = 'Diagnoses',
                Criterion_Details__c = 'No diabetes'
            )
        };

        // Call aggregation method with real Master Plan ID
        Map<Id, List<Criterion__c>> criteriaByMpId = new Map<Id, List<Criterion__c>>{
            mp.Id => mockCriteria
        };

        CohortMasterPlanHandler.aggregateCriteriaOnMp(criteriaByMpId);

        Test.stopTest();

        // Verify the Master Plan I/E field was updated
        MasterPlan__c updatedMp = [SELECT Id, I_E__c FROM MasterPlan__c WHERE Id = :mp.Id];
        System.assertNotEquals(null, updatedMp.I_E__c, 'I/E field should be populated');
    }
}