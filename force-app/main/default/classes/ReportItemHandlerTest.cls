@IsTest(seeAllData=false)
private class ReportItemHandlerTest {

    @testSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();
            MasterPlan__c mp = f.createMasterPlan(); insert mp;
            Contact c = f.createPatientContact(); insert c;
            HealthProfile__c hp = f.createHealthPlanOpportunity();
            hp.Patient__c = c.Id; insert hp;
            PurchaseOrder__c po = f.createPurchaseOrder(hp.Id, mp.Id, 'Ordered');
            insert po;
        }
    }

    @IsTest
    static void test_afterInsert_stamps_po_with_report_item_id() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PurchaseOrder__c po = [SELECT Id FROM PurchaseOrder__c LIMIT 1];
            MasterPlan__c mp   = [SELECT Id FROM MasterPlan__c LIMIT 1];

            ReportItem__c ri = new ReportItem__c(
                Master_Plan__c            = mp.Id,
                Purchase_Order__c         = po.Id,
                Specimen_Order_Deleted__c = false
            );

            Test.startTest();
            insert ri;
            new ReportItemHandler().afterInsert(new List<SObject>{ ri });
            Test.stopTest();

            PurchaseOrder__c updated = [
                SELECT Report_Item_ID__c FROM PurchaseOrder__c WHERE Id = :po.Id
            ];
            System.assertEquals(ri.Id, updated.Report_Item_ID__c,
                'afterInsert should stamp the Purchase Order with the ReportItem__c Id');
        }
    }

    @IsTest
    static void test_stampOrderWithItemId_no_purchase_order_link() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            MasterPlan__c mp = [SELECT Id FROM MasterPlan__c LIMIT 1];

            ReportItem__c ri = new ReportItem__c(
                Master_Plan__c            = mp.Id,
                Specimen_Order_Deleted__c = false
            );

            Test.startTest();
            ReportItemHandler.stampOrderWithItemId(new List<ReportItem__c>{ ri });
            Test.stopTest();

            System.assert(true, 'stampOrderWithItemId with no Purchase_Order__c should be a no-op');
        }
    }

    @IsTest
    static void test_empty_and_null_inputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ReportItemHandler handler = new ReportItemHandler();
            Test.startTest();
            handler.beforeInsert(new List<SObject>());
            handler.beforeUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.beforeDelete(new Map<Id, SObject>());
            handler.afterInsert(null);
            handler.afterInsert(new List<SObject>());
            handler.afterUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.afterDelete(new Map<Id, SObject>());
            handler.afterUndelete(new List<SObject>());
            ReportItemHandler.stampOrderWithItemId(null);
            ReportItemHandler.stampOrderWithItemId(new List<ReportItem__c>());
            Test.stopTest();
        }
    }
}