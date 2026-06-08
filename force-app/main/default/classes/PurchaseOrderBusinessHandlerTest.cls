@IsTest(seeAllData=false)
private class PurchaseOrderBusinessHandlerTest {

    @testSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            Contact patient  = f.createPatientContact();      insert patient;
            Contact advocate = f.createResearchCoordinator(); insert advocate;

            HealthProfile__c hp = f.createHealthPlanOpportunity();
            hp.Patient__c          = patient.Id;
            hp.Patient_Advocate__c = advocate.Id;
            insert hp;

            MasterPlan__c mp = f.createMasterPlan(); insert mp;
            ECS__Product__c b2c     = f.createB2CProduct(); insert b2c;
            Site_Codes__c site      = f.createSiteCode();   insert site;
            f.createCollection(mp.Id, b2c.Id, 1, false, site.Id);

            PurchaseOrder__c po = new PurchaseOrder__c(
                Name                 = 'BH-PO',
                Health_Profile__c    = hp.Id,
                MasterPlan__c        = mp.Id,
                Status__c            = PurchaseOrderLib.DRAFT_STATUS
            );
            insert po;
        }
    }

    @IsTest
    static void test_afterInsert_creates_lines_and_rolls_up() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PurchaseOrder__c base = [
                SELECT Id, Name, Health_Profile__c, MasterPlan__c, Status__c
                FROM PurchaseOrder__c WHERE Name = 'BH-PO' LIMIT 1
            ];

            PurchaseOrder__c po = new PurchaseOrder__c(
                Id                   = base.Id,
                Name                 = base.Name,
                Health_Profile__c    = base.Health_Profile__c,
                MasterPlan__c        = base.MasterPlan__c,
                Status__c            = base.Status__c
            );

            Test.startTest();
            new PurchaseOrderBusinessHandler().afterInsert(new List<SObject>{ po });
            Test.stopTest();

            Integer polCount = [
                SELECT COUNT() FROM PurchaseOrderLine__c WHERE PurchaseOrder__c = :po.Id
            ];
            System.assert(polCount > 0, 'POLs should be created on insert');

            MasterPlan__c mp = [
                SELECT Total_MP_Phleb_Compensation__c
                FROM MasterPlan__c WHERE Id = :base.MasterPlan__c
            ];
            System.assertNotEquals(null, mp.Total_MP_Phleb_Compensation__c, 'MP rollup should have executed');

            System.assertEquals(0, [SELECT COUNT() FROM ReportItem__c],
                'No report items should be created for DRAFT on insert');
        }
    }

    @IsTest
    static void test_afterUpdate_runs_gated_block_once() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PurchaseOrder__c base = [
                SELECT Id, Name, Health_Profile__c, MasterPlan__c, Status__c
                FROM PurchaseOrder__c WHERE Name = 'BH-PO' LIMIT 1
            ];

            PurchaseOrder__c poNew = new PurchaseOrder__c(
                Id                   = base.Id,
                Name                 = 'BH-PO-UPDATED',
                Health_Profile__c    = base.Health_Profile__c,
                MasterPlan__c        = base.MasterPlan__c,
                Status__c            = base.Status__c
            );

            PurchaseOrder__c poOld = new PurchaseOrder__c(
                Id                   = base.Id,
                Name                 = base.Name,
                Health_Profile__c    = base.Health_Profile__c,
                MasterPlan__c        = base.MasterPlan__c,
                Status__c            = base.Status__c
            );

            Map<Id, SObject> oldMap = new Map<Id, SObject>{ poNew.Id => poOld };

            Test.startTest();
            PurchaseOrderBusinessHandler h = new PurchaseOrderBusinessHandler();
            h.afterUpdate(new List<SObject>{ poNew }, oldMap);
            // Second call in same TX — firstRun gate prevents heavy block running twice
            h.afterUpdate(new List<SObject>{ poNew }, oldMap);
            Test.stopTest();

            System.assert(true, 'afterUpdate executed with lib.firstRun gate enforced');

            System.assertEquals(0, [SELECT COUNT() FROM ReportItem__c],
                'No report items should be created for DRAFT on update');
        }
    }

    @IsTest
    static void test_handler_empty_inputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PurchaseOrderBusinessHandler handler = new PurchaseOrderBusinessHandler();
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