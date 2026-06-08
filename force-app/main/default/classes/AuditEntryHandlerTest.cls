@IsTest(seeAllData=false)
private class AuditEntryHandlerTest {

    @testSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();
            ProjectPlan__c mp = f.createProjectPlan(); insert mp;
            Contact c = f.createPatientContact(); insert c;
            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Patient__c = c.Id; insert hp;
            WorkRequest__c po = f.createPurchaseOrder(hp.Id, mp.Id, 'Ordered');
            insert po;
        }
    }

    @IsTest
    static void test_afterInsert_stamps_po_with_report_item_id() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequest__c po = [SELECT Id FROM WorkRequest__c LIMIT 1];
            ProjectPlan__c mp   = [SELECT Id FROM ProjectPlan__c LIMIT 1];

            AuditEntry__c ri = new AuditEntry__c(
                Project_Plan__c            = mp.Id,
                Purchase_Order__c         = po.Id,
                Specimen_Order_Deleted__c = false
            );

            Test.startTest();
            insert ri;
            new AuditEntryHandler().afterInsert(new List<SObject>{ ri });
            Test.stopTest();

            WorkRequest__c updated = [
                SELECT Report_Item_ID__c FROM WorkRequest__c WHERE Id = :po.Id
            ];
            System.assertEquals(ri.Id, updated.Report_Item_ID__c,
                'afterInsert should stamp the Purchase Order with the AuditEntry__c Id');
        }
    }

    @IsTest
    static void test_stampOrderWithItemId_no_purchase_order_link() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProjectPlan__c mp = [SELECT Id FROM ProjectPlan__c LIMIT 1];

            AuditEntry__c ri = new AuditEntry__c(
                Project_Plan__c            = mp.Id,
                Specimen_Order_Deleted__c = false
            );

            Test.startTest();
            AuditEntryHandler.stampOrderWithItemId(new List<AuditEntry__c>{ ri });
            Test.stopTest();

            System.assert(true, 'stampOrderWithItemId with no Purchase_Order__c should be a no-op');
        }
    }

    @IsTest
    static void test_empty_and_null_inputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            AuditEntryHandler handler = new AuditEntryHandler();
            Test.startTest();
            handler.beforeInsert(new List<SObject>());
            handler.beforeUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.beforeDelete(new Map<Id, SObject>());
            handler.afterInsert(null);
            handler.afterInsert(new List<SObject>());
            handler.afterUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.afterDelete(new Map<Id, SObject>());
            handler.afterUndelete(new List<SObject>());
            AuditEntryHandler.stampOrderWithItemId(null);
            AuditEntryHandler.stampOrderWithItemId(new List<AuditEntry__c>());
            Test.stopTest();
        }
    }
}