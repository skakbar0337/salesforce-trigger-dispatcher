@IsTest
private class ProjectPlanExportHandlerTest {

    @IsTest
    static void testTriggerHandlerMethods() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory factory = new TestDataFactory();

            List<ProjectPlan__c> toInsert = new List<ProjectPlan__c>();
            for (Integer i = 0; i < 5; i++) {
                toInsert.add(factory.createProjectPlan());
            }

            List<ProjectPlan__c> projectPlans = new List<ProjectPlan__c>();
            for (Integer i = 0; i < 50; i++) {
                projectPlans.add(factory.createProjectPlan());
            }
            insert projectPlans;

            Map<Id, SObject> oldMap = new Map<Id, SObject>();
            for (ProjectPlan__c mp : projectPlans) {
                oldMap.put(mp.Id, mp.clone(false, true, false, false));
            }

            ProjectPlanExportHandler handler = new ProjectPlanExportHandler();

            Test.startTest();
            handler.beforeInsert(toInsert);
            handler.afterUpdate(projectPlans, oldMap);
            handler.afterDelete(oldMap);
            handler.afterUndelete(projectPlans);
            handler.beforeUpdate(projectPlans, oldMap);
            handler.beforeDelete(oldMap);
            handler.afterInsert(projectPlans);
            Test.stopTest();
        }
    }
}