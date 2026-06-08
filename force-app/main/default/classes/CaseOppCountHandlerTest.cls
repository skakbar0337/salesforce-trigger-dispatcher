@IsTest(seeAllData=false)
public class CaseOppCountHandlerTest {

    @IsTest
    static void test_opp_case_count_insert_update_delete_undelete() {
        TestDataFactory f = new TestDataFactory();

        // Two opps, each with a Master Plan
        Opportunity oppA = f.createOpportunity(); insert oppA;
        ProjectPlan__c mpA = f.createProjectPlan(); mpA.Opportunity__c = oppA.Id; insert mpA;

        Opportunity oppB = f.createOpportunity(); insert oppB;
        ProjectPlan__c mpB = f.createProjectPlan(); mpB.Opportunity__c = oppB.Id; insert mpB;

        // Two cases under mpA
        Case c1 = new Case(Subject='A1', Status='New', Origin='Phone', Project_Plan__c=mpA.Id);
        Case c2 = new Case(Subject='A2', Status='New', Origin='Phone', Project_Plan__c=mpA.Id);

        Test.startTest();

        insert new List<Case>{ c1, c2 };

        Opportunity oppA_afterInsert = [
            SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :oppA.Id
        ];
        System.assertEquals(2, (Decimal) (oppA_afterInsert.Number_of_cases__c == null ? 0 : oppA_afterInsert.Number_of_cases__c),
                            'Opp A should show 2 cases after insert');

        // Move one Case from mpA → mpB (afterUpdate should touch both Opps)
        c1 = [SELECT Id, Project_Plan__c FROM Case WHERE Id = :c1.Id];
        c1.Project_Plan__c = mpB.Id;
        update c1;

        Opportunity oppA_afterMove = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :oppA.Id];
        Opportunity oppB_afterMove = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :oppB.Id];

        System.assertEquals(1, (Decimal) (oppA_afterMove.Number_of_cases__c == null ? 0 : oppA_afterMove.Number_of_cases__c),
                            'Opp A should decrement to 1 after move');
        System.assertEquals(1, (Decimal) (oppB_afterMove.Number_of_cases__c == null ? 0 : oppB_afterMove.Number_of_cases__c),
                            'Opp B should increment to 1 after move');

        // Delete both; touched Opps should be set to 0 (afterDelete with old rows)
        delete new List<Case>{ c1, c2 };

        Opportunity oppA_afterDelete = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :oppA.Id];
        Opportunity oppB_afterDelete = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :oppB.Id];

        System.assertEquals(0, (Decimal) (oppA_afterDelete.Number_of_cases__c == null ? 0 : oppA_afterDelete.Number_of_cases__c),
                            'Opp A should be zeroed after delete');
        System.assertEquals(0, (Decimal) (oppB_afterDelete.Number_of_cases__c == null ? 0 : oppB_afterDelete.Number_of_cases__c),
                            'Opp B should be zeroed after delete');

        // Undelete both; counts should restore to last state (1 under each Opp)
        undelete new List<Case>{ c1, c2 };

        Test.stopTest();

        Opportunity oppA_final = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :oppA.Id];
        Opportunity oppB_final = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :oppB.Id];

        System.assertEquals(1, (Decimal) (oppA_final.Number_of_cases__c == null ? 0 : oppA_final.Number_of_cases__c),
                            'Opp A should restore to 1 after undelete');
        System.assertEquals(1, (Decimal) (oppB_final.Number_of_cases__c == null ? 0 : oppB_final.Number_of_cases__c),
                            'Opp B should restore to 1 after undelete');
    }
}