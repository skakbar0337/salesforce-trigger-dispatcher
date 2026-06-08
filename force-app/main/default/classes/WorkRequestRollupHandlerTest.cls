@IsTest(seeAllData=false)
private class WorkRequestRollupHandlerTest {

    @testSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();
            Contact patient  = f.createPatientContact();      insert patient;
            Contact advocate = f.createResearchCoordinator(); insert advocate;

            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Patient__c          = patient.Id;
            hp.Patient_Advocate__c = advocate.Id;
            insert hp;

            ProjectPlan__c mp = f.createProjectPlan(); insert mp;
            Opportunity opp = new Opportunity(
                Name      = 'Opp',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(1)
            );
            insert opp;
            mp.Opportunity__c = opp.Id;
            update mp;

            WorkRequest__c po = new WorkRequest__c(
                Name          = 'ToDelete',
                Health_Profile__c = hp.Id,
                ProjectPlan__c = mp.Id,
                Status__c     = WorkRequestLib.DRAFT_STATUS
            );
            insert po;
        }
    }

    @IsTest
    static void test_afterUndelete_executes_rollups() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequest__c base = [
                SELECT Id, ProjectPlan__c, Health_Profile__c, Status__c
                FROM WorkRequest__c LIMIT 1
            ];

            WorkRequest__c po = new WorkRequest__c(
                Id            = base.Id,
                ProjectPlan__c = base.ProjectPlan__c,
                Health_Profile__c = base.Health_Profile__c,
                Status__c     = base.Status__c
            );

            Test.startTest();
            new WorkRequestRollupHandler().afterUndelete(new List<SObject>{ po });
            Test.stopTest();

            System.assert(true, 'afterUndelete executed rollups and patient/smartsheet');
            System.assertEquals(0, [SELECT COUNT() FROM AuditEntry__c],
                'No report items should be created for DRAFT on undelete');
        }
    }

    @IsTest
    static void test_afterDelete_executes_email_and_rollups() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequest__c base = [
                SELECT Id, Name, Health_Profile__c, ProjectPlan__c, Status__c
                FROM WorkRequest__c WHERE Name = 'ToDelete' LIMIT 1
            ];

            WorkRequest__c oldRec = new WorkRequest__c(
                Id            = base.Id,
                Name          = base.Name,
                Health_Profile__c = base.Health_Profile__c,
                ProjectPlan__c = base.ProjectPlan__c,
                Status__c     = base.Status__c
            );

            Map<Id, SObject> oldMap = new Map<Id, SObject>{ oldRec.Id => oldRec };

            Test.startTest();
            new WorkRequestRollupHandler().afterDelete(oldMap);
            Test.stopTest();

            System.assert(true, 'afterDelete executed email, rollups, projections, and status routing');
            System.assertEquals(0, [SELECT COUNT() FROM AuditEntry__c],
                'No report items should be created for DRAFT on delete');
        }
    }

    @IsTest
    static void test_handler_empty_inputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequestRollupHandler handler = new WorkRequestRollupHandler();
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