@IsTest
public class CasePlanErrorAggregateHandlerTest {

    private static Id getPhlebotomistRecordTypeId() {
        return [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Contact' 
            AND Name = 'Phlebotomist' 
            LIMIT 1
        ].Id;
    }

    private static Opportunity createTestOpportunity() {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert opp;
        return opp;
    }

    private static ProjectPlan__c createTestMasterPlan(Id oppId) {
        ProjectPlan__c mp = new ProjectPlan__c(
            Name = 'Test Master Plan',
            Opportunity__c = oppId
        );
        insert mp;
        return mp;
    }

    private static Case createTestCase(
        Id projectPlanId,
        String errorSource,
        String errorType,
        String impactEffect,
        Boolean addPhleb
    ) {
        String uniqueSuffix = String.valueOf(Datetime.now().getTime());
        Case c = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Origin = 'Phone',
            Project_Plan__c = projectPlanId,
            Error_Source__c = errorSource,
            Error_Type__c = errorType,
            Impact_Effect__c = impactEffect,
            Lev_1_Responsible_Party__c = 'Partner-contracted Specialist',
            Date_Issue_Discovered__c = Date.today()
        );
        if (addPhleb) {
            Contact testPhleb = new Contact(
                FirstName = 'Test',
                LastName = 'Phleb' + uniqueSuffix,
                Email = 'testphleb' + uniqueSuffix + '@example.com',
                Phone = '123456' + uniqueSuffix.right(4),
                RecordTypeId = getPhlebotomistRecordTypeId()
            );
            insert testPhleb;
            c.Phlebotomist__c = testPhleb.Id;
        }
        return c;
    }

    @IsTest
    static void testCaseTrigger_AllScenarios() {
        Opportunity opp = createTestOpportunity();
        ProjectPlan__c mp = createTestMasterPlan(opp.Id);

        // Insert cases
        List<Case> cases = new List<Case>{
            createTestCase(mp.Id, 'Client', 'Sample error - blood collection', 'Client-Facing Impact', true),
            createTestCase(mp.Id, 'Phlebotomist', 'Administrative Error', 'Internal Impact', true)
        };

        Test.startTest();
        insert cases;

        // Validate Opportunity__c populated
        for (Case c : [SELECT Id, Opportunity__c FROM Case WHERE Id IN :cases]) {
            System.assertNotEquals(null, c.Opportunity__c, 'Opportunity__c should be populated');
        }

        // Update Cases → test rollups
        ProjectPlan__c newMp = createTestMasterPlan(opp.Id);
        for (Case c : cases) {
            c.Error_Source__c = 'Internal';
            c.Error_Type__c = 'Shipping error - specimen';
            c.Project_Plan__c = newMp.Id;
        }
        update cases;

        // Delete and undelete
        delete cases;
        undelete cases;
        Test.stopTest();

        // Validate Opportunity case count updated
        Opportunity updatedOpp = [
            SELECT Id, Number_of_cases__c 
            FROM Opportunity 
            WHERE Id = :newMp.Opportunity__c
        ];
        System.assertEquals(
            cases.size(), 
            updatedOpp.Number_of_cases__c, 
            'Case count should match after undelete'
        );
    }

    @IsTest
    static void testSkipCaseForPhlebNullAndStudyParticipant() {
        Opportunity opp = createTestOpportunity();
        ProjectPlan__c mp = createTestMasterPlan(opp.Id);

        Case c = new Case(
            Subject = 'Case - No Phleb',
            Status = 'New',
            Origin = 'Phone',
            Project_Plan__c = mp.Id,
            Error_Source__c = 'Client',
            Error_Type__c = 'Other',
            Impact_Effect__c = 'Internal Impact',
            Lev_1_Responsible_Party__c = 'Study Participant', 
            Date_Issue_Discovered__c = Date.today()
        );

        Test.startTest();
        insert c;
        Test.stopTest();

        ProjectPlan__c refreshedMp = [
            SELECT Id, Error_Source_Client__c
            FROM ProjectPlan__c
            WHERE Id = :mp.Id
        ];
        Integer actualCount = refreshedMp.Error_Source_Client__c == null 
            ? 0 
            : Integer.valueOf(refreshedMp.Error_Source_Client__c);
        System.assertEquals(
            0, 
            actualCount, 
            'Skip rule: Case with no Phleb + Study Participant should not increment rollups'
        );
    }
}