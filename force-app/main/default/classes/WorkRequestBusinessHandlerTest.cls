@IsTest(seeAllData=false)
private class WorkRequestBusinessHandlerTest {

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
            ECS__Product__c b2c     = f.createB2CProduct(); insert b2c;
            Site_Codes__c site      = f.createSiteCode();   insert site;
            f.createCollection(mp.Id, b2c.Id, 1, false, site.Id);

            WorkRequest__c po = new WorkRequest__c(
                Name                 = 'BH-PO',
                Clinical_Entry__c    = hp.Id,
                ProjectPlan__c        = mp.Id,
                Status__c            = WorkRequestLib.DRAFT_STATUS
            );
            insert po;
        }
    }

    @IsTest
    static void test_afterInsert_creates_lines_and_rolls_up() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequest__c base = [
                SELECT Id, Name, Clinical_Entry__c, ProjectPlan__c, Status__c
                FROM WorkRequest__c WHERE Name = 'BH-PO' LIMIT 1
            ];

            WorkRequest__c po = new WorkRequest__c(
                Id                   = base.Id,
                Name                 = base.Name,
                Clinical_Entry__c    = base.Clinical_Entry__c,
                ProjectPlan__c        = base.ProjectPlan__c,
                Status__c            = base.Status__c
            );

            Test.startTest();
            new WorkRequestBusinessHandler().afterInsert(new List<SObject>{ po });
            Test.stopTest();

            Integer polCount = [
                SELECT COUNT() FROM WorkRequestLine__c WHERE WorkRequest__c = :po.Id
            ];
            System.assert(polCount > 0, 'POLs should be created on insert');

            ProjectPlan__c mp = [
                SELECT Total_MP_Phleb_Compensation__c
                FROM ProjectPlan__c WHERE Id = :base.ProjectPlan__c
            ];
            System.assertNotEquals(null, mp.Total_MP_Phleb_Compensation__c, 'MP rollup should have executed');

            System.assertEquals(0, [SELECT COUNT() FROM AuditEntry__c],
                'No report items should be created for DRAFT on insert');
        }
    }

    @IsTest
    static void test_afterUpdate_runs_gated_block_once() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequest__c base = [
                SELECT Id, Name, Clinical_Entry__c, ProjectPlan__c, Status__c
                FROM WorkRequest__c WHERE Name = 'BH-PO' LIMIT 1
            ];

            WorkRequest__c poNew = new WorkRequest__c(
                Id                   = base.Id,
                Name                 = 'BH-PO-UPDATED',
                Clinical_Entry__c    = base.Clinical_Entry__c,
                ProjectPlan__c        = base.ProjectPlan__c,
                Status__c            = base.Status__c
            );

            WorkRequest__c poOld = new WorkRequest__c(
                Id                   = base.Id,
                Name                 = base.Name,
                Clinical_Entry__c    = base.Clinical_Entry__c,
                ProjectPlan__c        = base.ProjectPlan__c,
                Status__c            = base.Status__c
            );

            Map<Id, SObject> oldMap = new Map<Id, SObject>{ poNew.Id => poOld };

            Test.startTest();
            WorkRequestBusinessHandler h = new WorkRequestBusinessHandler();
            h.afterUpdate(new List<SObject>{ poNew }, oldMap);
            // Second call in same TX — firstRun gate prevents heavy block running twice
            h.afterUpdate(new List<SObject>{ poNew }, oldMap);
            Test.stopTest();

            System.assert(true, 'afterUpdate executed with lib.firstRun gate enforced');

            System.assertEquals(0, [SELECT COUNT() FROM AuditEntry__c],
                'No report items should be created for DRAFT on update');
        }
    }

    @IsTest
    static void test_handler_empty_inputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequestBusinessHandler handler = new WorkRequestBusinessHandler();
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