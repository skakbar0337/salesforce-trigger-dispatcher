@IsTest(seeAllData=false)
private class WorkRequestFieldHandlerTest {

    @IsTest
    static void test_handler_before_methods() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            ProjectPlan__c mp = f.createProjectPlan();
            insert mp;

            Contact c = f.createPatientContact(); insert c;
            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Patient__c = c.Id; insert hp;

            // -------- BEFORE INSERT --------
            WorkRequest__c po = new WorkRequest__c(
                Name                 = 'H-BI',
                ClinicalEntry__c     = hp.Id,
                ProjectPlan__c        = mp.Id,
                Amount_Paid__c       = '$9',
                Date_of_Payment__c   = Date.today()
            );

            new WorkRequestFieldHandler().beforeInsert(new List<SObject>{ po });

            System.assertEquals(hp.Id, po.Clinical_Entry__c,
                'HP should be copied from ClinicalEntry__c on BI');
            System.assertEquals(9, po.Amount_Paid_Number__c,
                'Currency string should be parsed to decimal on BI');

            // -------- BEFORE UPDATE --------
            insert po;

            WorkRequest__c oldRec = po.clone(false, true, false, false);
            oldRec.Status__c = WorkRequestLib.DRAFT_STATUS;

            po.Status__c          = WorkRequestLib.COMPLETED_STATUS;
            po.Amount_Paid__c     = '$11';
            po.Date_of_Payment__c = Date.today();

            Map<Id, SObject> oldMap = new Map<Id, SObject>{ po.Id => oldRec };

            new WorkRequestFieldHandler().beforeUpdate(new List<SObject>{ po }, oldMap);

            System.assertEquals(11, po.Amount_Paid_Number__c,
                'Amount_Paid__c should be parsed to numeric on BU');
            System.assertEquals(Date.today(), po.Completion_Date__c,
                'Completion date should be stamped when status first becomes Complete');
        }
    }

    @IsTest
    static void test_handler_empty_inputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            WorkRequestFieldHandler handler = new WorkRequestFieldHandler();
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