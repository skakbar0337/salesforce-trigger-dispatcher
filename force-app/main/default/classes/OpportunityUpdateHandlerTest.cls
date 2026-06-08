@IsTest(seeAllData=false)
private class OpportunityUpdateHandlerTest {

    /**
     * @description Auto-approve custom I/E criteria when Stage 2 -> Stage 3
     */
    @IsTest
    static void test_afterUpdate_auto_approve_ie_criteria() {
        TestDataFactory f = new TestDataFactory();
    
        // Users required by Stage 2 validation
        User csmUser = f.createUser(); insert csmUser;
        User devUser = f.createUser2('APD_Test'); insert devUser;
    
        // Stage 2 Opp with all required fields
        Opportunity o = new Opportunity(
            Name = 'I/E Approve',
            StageName = 'Stage 2 - Request Complete/Feasibility Review',
            CloseDate = Date.today().addDays(60),
            Proposal_Due_Date__c = Date.today().addDays(14),
            CSM__c = csmUser.Id,
            Assigned_Proposal_Developer__c = devUser.Id
        );
        insert o;
    
        // Master Plan (needed for Cohort / BidRecord__c)
        ProjectPlan__c mp = f.createProjectPlan(); insert mp;

        // Create a Cohort (actual API name = BidRecord__c)
        BidRecord__c cohort = new BidRecord__c(
            Project_Plan__c = mp.Id,
            BidRecord__c = o.Id,
            RecordTypeId = Schema.SObjectType.BidRecord__c
                .getRecordTypeInfosByName()
                .get('Cohort Standard').getRecordTypeId()
        );
        insert cohort;

        // Create Criterion with all required fields
        Criterion__c crit = new Criterion__c(
            Is_Custom__c = true,
            Status__c = 'New',
            Opportunity__c = o.Id,
            SubjectGroup__c = cohort.Id,
            Attribute_Type__c = 'Diagnoses',
            Criterion_Type__c = 'Inclusion'
        );
        insert crit;
    
        // Let the trigger framework run: Stage 2 -> Stage 3 transition
        Test.startTest();
        o.StageName = 'Stage 3 - Feasibility Approved/Proposal Delivery';
        update o;
        Test.stopTest();
    
        // Verify criterion auto-approved
        Criterion__c updated = [
            SELECT Id, Status__c
            FROM Criterion__c
            WHERE Id = :crit.Id
        ];
        System.assertEquals('Approved', updated.Status__c,
            'Custom I/E criterion should auto-approve on Stage 2 -> Stage 3');
    }

    @IsTest
    static void test_afterUpdate_no_stage_transition() {
        Opportunity o = new Opportunity(
            Name = 'No Transition',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert o;

        Test.startTest();
        o.Name = 'No Transition Updated';
        update o;
        Test.stopTest();

        System.assert(true, 'No exception when no stage transition occurs');
    }

    @IsTest
    static void test_interfaceHooks_noop() {
        Opportunity o = new Opportunity(
            Name = 'Hook Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert o;

        Test.startTest();
        OpportunityUpdateHandler handler = new OpportunityUpdateHandler();
        handler.beforeInsert(new List<SObject>{ o });
        handler.beforeUpdate(new List<SObject>{ o }, new Map<Id, SObject>{ o.Id => o });
        handler.beforeDelete(new Map<Id, SObject>{ o.Id => o });
        handler.afterInsert(new List<SObject>{ o });
        handler.afterDelete(new Map<Id, SObject>{ o.Id => o });
        handler.afterUndelete(new List<SObject>{ o });
        Test.stopTest();
    }
}