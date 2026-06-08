@IsTest
private class MasterPlanRealTimeExportHandlerTest {

    @IsTest
    static void testTriggerHandlerMethods() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory factory = new TestDataFactory();

            List<MasterPlan__c> toInsert = new List<MasterPlan__c>();
            for (Integer i = 0; i < 5; i++) {
                toInsert.add(factory.createMasterPlan());
            }

            List<MasterPlan__c> masterPlans = new List<MasterPlan__c>();
            for (Integer i = 0; i < 50; i++) {
                masterPlans.add(factory.createMasterPlan());
            }
            insert masterPlans;

            Map<Id, SObject> oldMap = new Map<Id, SObject>();
            for (MasterPlan__c mp : masterPlans) {
                oldMap.put(mp.Id, mp.clone(false, true, false, false));
            }

            MasterPlanRealTimeExportHandler handler = new MasterPlanRealTimeExportHandler();

            Test.startTest();
            handler.beforeInsert(toInsert);
            handler.afterUpdate(masterPlans, oldMap);
            handler.afterDelete(oldMap);
            handler.afterUndelete(masterPlans);
            handler.beforeUpdate(masterPlans, oldMap);
            handler.beforeDelete(oldMap);
            handler.afterInsert(masterPlans);
            Test.stopTest();
        }
    }
}