@IsTest(seeAllData=false)
private class PurchaseOrderFieldUpdateHandlerTest {

    @IsTest
    static void test_handler_before_methods() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            MasterPlan__c mp = f.createMasterPlan();
            insert mp;

            Contact c = f.createPatientContact(); insert c;
            HealthProfile__c hp = f.createHealthPlanOpportunity();
            hp.Patient__c = c.Id; insert hp;

            // -------- BEFORE INSERT --------
            PurchaseOrder__c po = new PurchaseOrder__c(
                Name                 = 'H-BI',
                HealthProfile__c     = hp.Id,
                MasterPlan__c        = mp.Id,
                Amount_Paid__c       = '$9',
                Date_of_Payment__c   = Date.today()
            );

            new PurchaseOrderFieldUpdateHandler().beforeInsert(new List<SObject>{ po });

            System.assertEquals(hp.Id, po.Health_Profile__c,
                'HP should be copied from HealthProfile__c on BI');
            System.assertEquals(9, po.Amount_Paid_Number__c,
                'Currency string should be parsed to decimal on BI');

            // -------- BEFORE UPDATE --------
            insert po;

            PurchaseOrder__c oldRec = po.clone(false, true, false, false);
            oldRec.Status__c = PurchaseOrderLib.DRAFT_STATUS;

            po.Status__c          = PurchaseOrderLib.COMPLETED_STATUS;
            po.Amount_Paid__c     = '$11';
            po.Date_of_Payment__c = Date.today();

            Map<Id, SObject> oldMap = new Map<Id, SObject>{ po.Id => oldRec };

            new PurchaseOrderFieldUpdateHandler().beforeUpdate(new List<SObject>{ po }, oldMap);

            System.assertEquals(11, po.Amount_Paid_Number__c,
                'Amount_Paid__c should be parsed to numeric on BU');
            System.assertEquals(Date.today(), po.Completion_Date__c,
                'Completion date should be stamped when status first becomes Complete');
        }
    }

    @IsTest
    static void test_handler_empty_inputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PurchaseOrderFieldUpdateHandler handler = new PurchaseOrderFieldUpdateHandler();
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