@IsTest(seeAllData=false)
public class CaseAttributeUpdateHandlerTest {

    private static Id getPhlebotomistRtId() {
        for (RecordType rt : [
            SELECT Id, Name, DeveloperName FROM RecordType WHERE SObjectType = 'Contact'
        ]) {
            if (rt.Name == 'Phlebotomist' || rt.DeveloperName == 'Phlebotomist') return rt.Id;
        }
        return null;
    }

    @IsTest
    static void test_before_insert_and_before_update_MP_to_Opp_propagation() {
        TestDataFactory f = new TestDataFactory();

        // Create Opportunity and Master Plan records
        Opportunity opp1 = f.createOpportunity(); insert opp1;
        ProjectPlan__c mp1 = f.createProjectPlan(); mp1.Opportunity__c = opp1.Id; insert mp1;

        Opportunity opp2 = f.createOpportunity(); insert opp2;
        ProjectPlan__c mp2 = f.createProjectPlan(); mp2.Opportunity__c = opp2.Id; insert mp2;

        // BEFORE INSERT → Opportunity__c should populate from MP
        Case c = new Case(
            Subject = 'Field Map',
            Status  = 'New',
            Origin  = 'Phone',
            Master_Plan__c = mp1.Id
        );
        List<SObject> insertList = new List<SObject>{ c };
        new CaseAttributeUpdateHandler().beforeInsert(insertList);
        insert (List<Case>) ((List<SObject>) insertList);

        c = [SELECT Id, Opportunity__c FROM Case WHERE Id = :((Case) insertList[0]).Id];
        System.assertEquals(opp1.Id, c.Opportunity__c, 'beforeInsert should map MP → Opportunity');

        // BEFORE UPDATE → change to MP2 → Opp should be remapped
        c.Master_Plan__c = mp2.Id;
        List<SObject> updateList1 = new List<SObject>{ c };
        new CaseAttributeUpdateHandler().beforeUpdate(updateList1, null); // legacy ignores oldMap
        update (List<Case>) ((List<SObject>) updateList1);

        c = [SELECT Id, Opportunity__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(opp2.Id, c.Opportunity__c, 'beforeUpdate should remap to new MP → Opportunity');

        // BEFORE UPDATE → null Master_Plan__c → Opportunity__c remains unchanged (legacy behavior)
        c.Master_Plan__c = null;
        List<SObject> updateList2 = new List<SObject>{ c };
        new CaseAttributeUpdateHandler().beforeUpdate(updateList2, null); // oldMap still ignored
        update (List<Case>) ((List<SObject>) updateList2);

        c = [SELECT Id, Opportunity__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(opp2.Id, c.Opportunity__c,
            'Legacy behavior: null MP during beforeUpdate does NOT null Opportunity__c');
    }
}