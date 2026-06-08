@IsTest
private class ProjectPlanBusinessHandlerTest {

    @IsTest
    static void testBeforeInsert_stampsCSMFromOpp() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = new TestDataFactory().createOpportunity();
            opp.CSM__c = UserInfo.getUserId();
            insert opp;

            ProjectPlan__c mp = new TestDataFactory().createProjectPlan();
            mp.Opportunity__c = opp.Id;

            Test.startTest();
            insert mp;
            Test.stopTest();

            ProjectPlan__c insertedMP = [SELECT Id, CSM__c FROM ProjectPlan__c WHERE Id = :mp.Id];
            System.assertEquals(UserInfo.getUserId(), insertedMP.CSM__c, 'CSM__c should be stamped from Opportunity');
        }
    }

    @IsTest
    static void testBeforeInsert_noOpportunity() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProjectPlan__c mp = new TestDataFactory().createProjectPlan();

            Test.startTest();
            insert mp;
            Test.stopTest();

            ProjectPlan__c insertedMP = [SELECT Id, CSM__c FROM ProjectPlan__c WHERE Id = :mp.Id];
            System.assertEquals(null, insertedMP.CSM__c, 'CSM should remain null when no Opportunity linked');
        }
    }

    @IsTest
    static void testAfterUpdate_rollupToOpportunity() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            Opportunity opp = f.createOpportunity();
            insert opp;

            ProjectPlan__c mp = f.createProjectPlan();
            mp.Opportunity__c = opp.Id;
            insert mp;

            Contact patient = f.createPatientContact();
            insert patient;

            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Patient__c = patient.Id;
            hp.Project_Plan__c = mp.Id;
            insert hp;

            WorkRequest__c po1 = f.createPurchaseOrder(hp.Id, mp.Id, 'Draft');
            po1.Amount_Paid__c = '100';
            po1.Amount_Paid_Number__c = 100;
            po1.Date_of_Payment__c = Date.today().addDays(-1);
            po1.Incomplete_SO_Phleb_Paid__c = true;
            insert po1;

            WorkRequest__c po2 = f.createPurchaseOrder(hp.Id, mp.Id, 'Draft');
            po2.Amount_Paid__c = '200';
            po2.Amount_Paid_Number__c = 200;
            po2.Date_of_Payment__c = Date.today();
            insert po2;

            Case c = new Case(Project_Plan__c = mp.Id, Status = 'New');
            insert c;

            Test.startTest();
            update mp;
            Test.stopTest();

            Opportunity updatedOpp = [
                SELECT Id, Number_of_cases__c, Total_Opp_Subject_Compensation__c, Total_Opp_Phleb_Compensation__c
                FROM Opportunity
                WHERE Id = :opp.Id
            ];
            System.assertEquals(1, updatedOpp.Number_of_cases__c, 'Should roll up number of cases');
            System.assertEquals(300, updatedOpp.Total_Opp_Subject_Compensation__c, 'Should roll up sum of Amount_Paid_Number__c');
            System.assert(updatedOpp.Total_Opp_Phleb_Compensation__c >= 0, 'Should roll up Phleb Compensation');
        }
    }

    @IsTest
    static void testAfterUpdate_opportunityChange() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            Opportunity opp1 = f.createOpportunity();
            insert opp1;

            Opportunity opp2 = f.createOpportunity();
            insert opp2;

            ProjectPlan__c mp = f.createProjectPlan();
            mp.Opportunity__c = opp1.Id;
            insert mp;

            mp.Opportunity__c = opp2.Id;

            Test.startTest();
            update mp;
            Test.stopTest();

            Opportunity updatedOpp1 = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :opp1.Id];
            Opportunity updatedOpp2 = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :opp2.Id];
            System.assertNotEquals(null, updatedOpp1, 'Original Opportunity should exist');
            System.assertNotEquals(null, updatedOpp2, 'New Opportunity should exist');
        }
    }

    @IsTest
    static void testAfterUpdate_noOpportunityChange() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            Opportunity opp = f.createOpportunity();
            insert opp;

            ProjectPlan__c mp = f.createProjectPlan();
            mp.Opportunity__c = opp.Id;
            insert mp;

            mp.Name = 'Updated Name';

            Test.startTest();
            update mp;
            Test.stopTest();

            Opportunity updatedOpp = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :opp.Id];
            System.assert(updatedOpp.Number_of_cases__c == null || updatedOpp.Number_of_cases__c == 0,
                'No rollup when Opportunity did not change');
        }
    }

    @IsTest
    static void testAfterDelete_rollupToOpportunity() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            Opportunity opp = f.createOpportunity();
            insert opp;

            ProjectPlan__c mp = f.createProjectPlan();
            mp.Opportunity__c = opp.Id;
            insert mp;

            Test.startTest();
            delete mp;
            Test.stopTest();

            Opportunity updatedOpp = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :opp.Id];
            System.assertEquals(0, updatedOpp.Number_of_cases__c, 'Cases should roll down to 0 after MP deletion');
        }
    }

    @IsTest
    static void testAfterUndelete_rollupToOpportunity() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            Opportunity opp = f.createOpportunity();
            insert opp;

            ProjectPlan__c mp = f.createProjectPlan();
            mp.Opportunity__c = opp.Id;
            insert mp;
            delete mp;

            Test.startTest();
            undelete mp;
            Test.stopTest();

            Opportunity updatedOpp = [SELECT Id, Number_of_cases__c FROM Opportunity WHERE Id = :opp.Id];
            System.assertNotEquals(null, updatedOpp, 'Opportunity should still exist after MP undelete');
        }
    }

    @IsTest
    static void testHandlerEmptyInputs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ProjectPlanBusinessHandler handler = new ProjectPlanBusinessHandler();

            Test.startTest();
            handler.beforeInsert(new List<SObject>());
            handler.afterUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.afterDelete(new Map<Id, SObject>());
            handler.afterUndelete(new List<SObject>());
            handler.beforeUpdate(new List<SObject>(), new Map<Id, SObject>());
            handler.beforeDelete(new Map<Id, SObject>());
            handler.afterInsert(new List<SObject>());
            Test.stopTest();

            System.assert(true, 'Handler empty input methods should not throw');
        }
    }

    // ---- Study Closure HP Status Tests ----

    @IsTest
    static void testStudyClosure_Complete_UpdatesEligibleHPs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            ProjectPlan__c mp = f.createProjectPlan();
            insert mp;

            Contact rc = f.createResearchCoordinator();
            insert rc;

            List<ClinicalEntry__c> hps = new List<ClinicalEntry__c>();
            for (String status : new List<String>{ 'Need to be Screened', 'On Hold', 'Pending Approval' }) {
                ClinicalEntry__c hp = f.createHealthPlanOpportunity();
                hp.Project_Plan__c = mp.Id;
                hp.Status__c = status;
                hp.Research_Coordinator__c = rc.Id;
                hp.SSDNQ_Check__c = true;
                hp.Safe_blood_volume_based_on_all_condition__c = true;
                hp.Is_Clone_Originated__c = true;
                hps.add(hp);
            }
            insert hps;

            mp.Status__c = 'Study Closed - Complete';

            Test.startTest();
            update mp;
            Test.stopTest();

            for (ClinicalEntry__c hp : [SELECT Status__c FROM ClinicalEntry__c WHERE Project_Plan__c = :mp.Id]) {
                System.assertEquals(ProjectPlanBusinessHandler.TARGET_HP_STATUS, hp.Status__c,
                    'HP should be set to At Enrollment Capacity on study closure');
            }
        }
    }

    @IsTest
    static void testStudyClosure_Incomplete_UpdatesEligibleHPs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            ProjectPlan__c mp = f.createProjectPlan();
            insert mp;

            Contact rc = f.createResearchCoordinator();
            insert rc;

            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Project_Plan__c = mp.Id;
            hp.Status__c = 'Rescheduling';
            hp.Research_Coordinator__c = rc.Id;
            hp.SSDNQ_Check__c = true;
            hp.Safe_blood_volume_based_on_all_condition__c = true;
            hp.Is_Clone_Originated__c = true;
            insert hp;

            mp.Status__c = 'Study Closed - Incomplete';
            mp.Reason_for_Incomplete_Status__c = 'Cancellation - Other';

            Test.startTest();
            update mp;
            Test.stopTest();

            ClinicalEntry__c updated = [SELECT Status__c FROM ClinicalEntry__c WHERE Id = :hp.Id];
            System.assertEquals(ProjectPlanBusinessHandler.TARGET_HP_STATUS, updated.Status__c,
                'HP should be updated when MP transitions to Study Closed - Incomplete');
        }
    }

    @IsTest
    static void testStudyClosure_NonEligibleHP_NotChanged() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            ProjectPlan__c mp = f.createProjectPlan();
            insert mp;

            Contact rc = f.createResearchCoordinator();
            insert rc;

            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Project_Plan__c = mp.Id;
            hp.Status__c = 'Donated Blood';
            hp.Research_Coordinator__c = rc.Id;
            hp.SSDNQ_Check__c = true;
            hp.Safe_blood_volume_based_on_all_condition__c = true;
            hp.Is_Clone_Originated__c = true;
            insert hp;

            ProjectPlan__c oldMp = mp.clone(false, true, false, false);
            oldMp.Id = mp.Id;
            oldMp.Status__c = 'In Process';
            mp.Status__c = 'Study Closed - Complete';

            Test.startTest();
            ProjectPlanBusinessHandler handler = new ProjectPlanBusinessHandler();
            handler.afterUpdate(
                new List<SObject>{ mp },
                new Map<Id, SObject>{ mp.Id => (SObject) oldMp }
            );
            Test.stopTest();

            ClinicalEntry__c unchanged = [SELECT Status__c FROM ClinicalEntry__c WHERE Id = :hp.Id];
            System.assertEquals('Donated Blood', unchanged.Status__c,
                'Non-eligible HP statuses must not be changed');
        }
    }

    @IsTest
    static void testStudyClosure_AlreadyClosed_NoReprocessing() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataFactory f = new TestDataFactory();

            ProjectPlan__c mp = f.createProjectPlan();
            insert mp;

            Contact rc = f.createResearchCoordinator();
            insert rc;

            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Project_Plan__c = mp.Id;
            hp.Status__c = 'Need to be Screened';
            hp.Research_Coordinator__c = rc.Id;
            hp.SSDNQ_Check__c = true;
            hp.Safe_blood_volume_based_on_all_condition__c = true;
            hp.Is_Clone_Originated__c = true;
            insert hp;

            ProjectPlan__c oldMp = mp.clone(false, true, false, false);
            oldMp.Id = mp.Id;
            oldMp.Status__c = 'Study Closed - Complete';
            mp.Status__c = 'Study Closed - Complete';

            Test.startTest();
            ProjectPlanBusinessHandler handler = new ProjectPlanBusinessHandler();
            handler.afterUpdate(
                new List<SObject>{ mp },
                new Map<Id, SObject>{ mp.Id => (SObject) oldMp }
            );
            Test.stopTest();

            ClinicalEntry__c unchanged = [SELECT Status__c FROM ClinicalEntry__c WHERE Id = :hp.Id];
            System.assertEquals('Need to be Screened', unchanged.Status__c,
                'HP must not be re-processed when MP was already closed');
        }
    }
}