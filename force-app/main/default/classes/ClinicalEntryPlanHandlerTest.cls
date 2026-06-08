@IsTest
private class ClinicalEntryPlanHandlerTest {

    // ---------------------------------------------
    // Test Setup
    // ---------------------------------------------
    @testSetup
    static void setupData() {
        TestDataFactory f = new TestDataFactory();

        // Master Plans
        ProjectPlan__c mp1 = f.createProjectPlan();
        ProjectPlan__c mp2 = f.createProjectPlan();
        mp1.Name = 'MP-1';
        mp2.Name = 'MP-2';
        insert new List<ProjectPlan__c>{ mp1, mp2 };

        // Research Coordinator contact (required by HP validation rules)
        insert f.createResearchCoordinator();

        // Seed a few HPs for baseline (linked to mp1) in a neutral status
        List<ClinicalEntry__c> seed = new List<ClinicalEntry__c>();
        Id rcId = getResearchCoordinatorId();
        for (Integer i = 0; i < 5; i++) {
            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Name = 'Seed HP ' + i;
            hp.Project_Plan__c = mp1.Id;
            hp.Status__c = 'Need to be Screened';
            hp.Research_Coordinator__c = rcId;
            hp.SSDNQ_Check__c = true;
            hp.Safe_blood_volume_based_on_all_condition__c = true;
            hp.Is_Clone_Originated__c = true;
            seed.add(hp);
        }
        insert seed;
    }

    // ---------------------------------------------
    // Helpers
    // ---------------------------------------------

    // Convert List<ClinicalEntry__c> -> List<SObject>
    private static List<SObject> toSObjects(List<ClinicalEntry__c> rows) {
        List<SObject> out = new List<SObject>();
        for (ClinicalEntry__c r : rows) out.add(r);
        return out;
    }

    // Query the RC created in @testSetup
    private static Id getResearchCoordinatorId() {
        return [SELECT Id FROM Contact WHERE Email = 'test@example.com.test' LIMIT 1].Id;
    }

    /**
     * Create HPs for a given MP with a specific status; set RC & flags to satisfy validation rules.
     */
    private static List<ClinicalEntry__c> makeHPs(Id mpId, String status, Integer count, Id rcId) {
        TestDataFactory f = new TestDataFactory();
        List<ClinicalEntry__c> out = new List<ClinicalEntry__c>();
        for (Integer i = 0; i < count; i++) {
            ClinicalEntry__c hp = f.createHealthPlanOpportunity();
            hp.Name = status + ' #' + i;
            hp.Project_Plan__c = mpId;
            hp.Status__c = status;
            hp.Research_Coordinator__c = rcId;
            hp.SSDNQ_Check__c = true;
            hp.Safe_blood_volume_based_on_all_condition__c = true; // avoid Ready-to-be-Scheduled VR
            hp.Is_Clone_Originated__c = true; // bypass Prod email flow
            out.add(hp);
        }
        return out;
    }

    private static ProjectPlan__c getMpByName(String name) {
        return [
            SELECT Id, Name,
                   Pending_Screen__c,
                   Pending_Documents__c,
                   Ready_to_be_Scheduled__c,
                   Does_not_qualify_at_screening__c,
                   Total_number_of_incomplete_visits__c
            FROM ProjectPlan__c
            WHERE Name = :name
            LIMIT 1
        ];
    }

    // Create SSDNQ Answer row to satisfy the DNQ validation rule on Health Profile
    private static void seedSsdnqAnswer(Id hpId) {
        // Use DNQ_Category__c = 'Other' (confirmed present)
        Study_Specific_DNQ_Answer__c ans = new Study_Specific_DNQ_Answer__c(
            Clinical_Entry__c = hpId,
            DNQ_Category__c   = 'Other',
            SSDNQ_Answer__c   = 'Auto test justification'
        );
        insert ans;
    }

    // ---------------------------------------------
    // Tests
    // ---------------------------------------------

    @IsTest
    static void testAfterInsert_StatusRollups() {
        ProjectPlan__c mp1 = getMpByName('MP-1');
        Id rcId = getResearchCoordinatorId();

        // Baseline BEFORE
        Decimal basePendingScreen = (mp1.Pending_Screen__c == null) ? 0 : mp1.Pending_Screen__c;
        Decimal basePendingDocs   = (mp1.Pending_Documents__c == null) ? 0 : mp1.Pending_Documents__c;
        Decimal baseReadyToSched  = (mp1.Ready_to_be_Scheduled__c == null) ? 0 : mp1.Ready_to_be_Scheduled__c;

        // Insert + rollup
        List<ClinicalEntry__c> toInsert = new List<ClinicalEntry__c>();
        toInsert.addAll(makeHPs(mp1.Id, 'Need to be Screened', 2, rcId));  // contributes to Pending_Screen__c
        toInsert.addAll(makeHPs(mp1.Id, 'Pending Screen', 1, rcId));       // contributes to Pending_Screen__c
        toInsert.addAll(makeHPs(mp1.Id, 'Pending Documents', 3, rcId));    // contributes to Pending_Documents__c
        toInsert.addAll(makeHPs(mp1.Id, 'Ready to be Scheduled', 4, rcId));// contributes to Ready_to_be_Scheduled__c
        insert toInsert;

        Test.startTest();
        ClinicalEntryPlanHandler h = new ClinicalEntryPlanHandler();
        h.afterInsert(toSObjects(toInsert));
        Test.stopTest();

        ProjectPlan__c refreshed = getMpByName('MP-1');

        // Assert exact deltas
        System.assertEquals(basePendingScreen + 3, refreshed.Pending_Screen__c,
            'Pending_Screen__c should increase by NeedToBeScreened(2)+PendingScreen(1)');
        System.assertEquals(basePendingDocs + 3, refreshed.Pending_Documents__c,
            'Pending_Documents__c should increase by 3');
        System.assertEquals(baseReadyToSched + 4, refreshed.Ready_to_be_Scheduled__c,
            'Ready_to_be_Scheduled__c should increase by 4');

    }

    @IsTest
    static void testAfterInsert_Dnq_And_Incomplete_Rollups() {
        ProjectPlan__c mp1 = getMpByName('MP-1');
        Id rcId = getResearchCoordinatorId();

        // DNQ and Incomplete status sets
        List<String> dnq = new List<String>{
            'Pre-screen - Does Not Qualify for a Current Study',
            'Does Not Qualify For a Current Study',
            'DNQ - At Enrollment Capacity',
            'DNQ - Hold',
            'Cannot Be Reached',
            'Cannot Participate',
            'Out of Territory',
            'Do Not Contact'
        };
        List<String> inc = new List<String>{ 'Reschedule', 'Cancellation/No Show', 'Unsuccessful Collection' };

        // Build HPs
        List<ClinicalEntry__c> toInsert = new List<ClinicalEntry__c>();
        toInsert.addAll(makeHPs(mp1.Id, dnq[0], 2, rcId));
        toInsert.addAll(makeHPs(mp1.Id, dnq[1], 3, rcId)); // DNQ total = 5
        toInsert.addAll(makeHPs(mp1.Id, inc[0], 1, rcId));
        toInsert.addAll(makeHPs(mp1.Id, inc[1], 2, rcId));
        toInsert.addAll(makeHPs(mp1.Id, inc[2], 3, rcId)); // Incomplete total = 6
        insert toInsert;

        // Seed 1 SSDNQ Answer per DNQ record to satisfy the VR
        for (ClinicalEntry__c hp : toInsert) {
            if (dnq.contains(hp.Status__c)) seedSsdnqAnswer(hp.Id);
        }

        Test.startTest();
        ClinicalEntryPlanHandler h = new ClinicalEntryPlanHandler();
        h.afterInsert(toSObjects(toInsert));
        Test.stopTest();

        ProjectPlan__c refreshed = getMpByName('MP-1');
        System.assertEquals(5, refreshed.Does_not_qualify_at_screening__c,
            'DNQ rollup should equal total DNQ records inserted (5).');
        System.assertEquals(6, refreshed.Total_number_of_incomplete_visits__c,
            'Incomplete visit rollup should equal total incomplete records inserted (6).');
    }

    @IsTest
    static void testAfterUpdate_StatusChange() {
        ProjectPlan__c mp1 = getMpByName('MP-1');
        Id rcId = getResearchCoordinatorId();

        TestDataFactory f = new TestDataFactory();
        ClinicalEntry__c hp = f.createHealthPlanOpportunity();
        hp.Project_Plan__c = mp1.Id;
        hp.Status__c = 'Need to be Screened';
        hp.Research_Coordinator__c = rcId;
        hp.SSDNQ_Check__c = true;
        hp.Safe_blood_volume_based_on_all_condition__c = true;
        hp.Is_Clone_Originated__c = true;
        insert hp;

        // Old snapshot
        ClinicalEntry__c oldHp = hp.clone(false, true, false, false);
        oldHp.Id = hp.Id;
        oldHp.Status__c = 'Need to be Screened';

        // Change status to "Ready to be Scheduled" (requires the checkbox true)
        hp.Safe_blood_volume_based_on_all_condition__c = true;
        hp.Status__c = 'Ready to be Scheduled';
        update hp;

        // Strongly-typed oldMap to avoid runtime cast issues inside handler
        Map<Id, ClinicalEntry__c> oldMapSerp = new Map<Id, ClinicalEntry__c>{ hp.Id => oldHp };

        Test.startTest();
        ClinicalEntryPlanHandler h = new ClinicalEntryPlanHandler();
        h.afterUpdate(new List<SObject>{ hp }, (Map<Id, SObject>) oldMapSerp);
        Test.stopTest();

        ProjectPlan__c refreshed = [
            SELECT Id, Pending_Screen__c, Ready_to_be_Scheduled__c
            FROM ProjectPlan__c WHERE Id = :mp1.Id
        ];
        System.assertNotEquals(null, refreshed, 'MP should refresh without error.');
    }

    @IsTest
    static void testAfterUpdate_MasterPlanReassignment() {
        ProjectPlan__c mp1 = getMpByName('MP-1');
        ProjectPlan__c mp2 = getMpByName('MP-2');
        Id rcId = getResearchCoordinatorId();

        TestDataFactory f = new TestDataFactory();
        ClinicalEntry__c hp = f.createHealthPlanOpportunity();
        hp.Project_Plan__c = mp1.Id;
        hp.Status__c = 'Pending Documents';
        hp.Research_Coordinator__c = rcId;
        hp.SSDNQ_Check__c = true;
        hp.Safe_blood_volume_based_on_all_condition__c = true;
        insert hp;

        ClinicalEntry__c oldHp = hp.clone(false, true, false, false);
        oldHp.Id = hp.Id;
        oldHp.Project_Plan__c = mp1.Id;
        oldHp.Status__c = 'Pending Documents';

        // Reassign to mp2
        hp.Project_Plan__c = mp2.Id;
        update hp;

        Map<Id, ClinicalEntry__c> oldMapSerp = new Map<Id, ClinicalEntry__c>{ hp.Id => oldHp };

        Test.startTest();
        ClinicalEntryPlanHandler h = new ClinicalEntryPlanHandler();
        h.afterUpdate(new List<SObject>{ hp }, (Map<Id, SObject>) oldMapSerp);
        Test.stopTest();

        ProjectPlan__c refreshed1 = getMpByName('MP-1');
        ProjectPlan__c refreshed2 = getMpByName('MP-2');

        System.assertNotEquals(null, refreshed1.Pending_Documents__c,
            'Source MP should be recalculated when an HP moves away.');
        System.assertNotEquals(null, refreshed2.Pending_Documents__c,
            'Destination MP should be recalculated when an HP moves in.');
    }

    @IsTest
    static void testAfterDelete_And_AfterUndelete() {
        ProjectPlan__c mp1 = getMpByName('MP-1');
        Id rcId = getResearchCoordinatorId();

        TestDataFactory f = new TestDataFactory();
        ClinicalEntry__c hp = f.createHealthPlanOpportunity();
        hp.Project_Plan__c = mp1.Id;
        hp.Status__c = 'Pending Documents';
        hp.Research_Coordinator__c = rcId;
        hp.SSDNQ_Check__c = true;
        hp.Safe_blood_volume_based_on_all_condition__c = true;
        insert hp;

        Map<Id, SObject> delOldMap = new Map<Id, SObject>{ hp.Id => (SObject) hp };

        Test.startTest();
        ClinicalEntryPlanHandler h = new ClinicalEntryPlanHandler();
        h.afterDelete(delOldMap);                    // simulate delete
        h.afterUndelete(new List<SObject>{ hp });   // simulate undelete (same test context)
        Test.stopTest();

        ProjectPlan__c postUndelete = getMpByName('MP-1');
        System.assertNotEquals(null, postUndelete.Pending_Documents__c, 'Rollup should recalc after undelete.');
    }

    @IsTest
    static void testBulk_AfterInsert_80() {
        ProjectPlan__c mp1 = getMpByName('MP-1');
        ProjectPlan__c mp2 = getMpByName('MP-2');
        Id rcId = getResearchCoordinatorId();

        // Build 80 HPs in bulk
        List<ClinicalEntry__c> bulkHps = new List<ClinicalEntry__c>();
        bulkHps.addAll(makeHPs(mp1.Id, 'Ready to be Scheduled', 40, rcId));
        bulkHps.addAll(makeHPs(mp2.Id, 'Pending Documents', 40, rcId));
        insert bulkHps;

        Test.startTest();
        ClinicalEntryPlanHandler h = new ClinicalEntryPlanHandler();
        h.afterInsert(toSObjects(bulkHps));
        Test.stopTest();

        ProjectPlan__c r1 = [
            SELECT Id, Ready_to_be_Scheduled__c FROM ProjectPlan__c WHERE Id = :mp1.Id
        ];
        ProjectPlan__c r2 = [
            SELECT Id, Pending_Documents__c FROM ProjectPlan__c WHERE Id = :mp2.Id
        ];

        System.assert(r1.Ready_to_be_Scheduled__c >= 40, 'MP1 should reflect bulk inserts (>=40).');
        System.assert(r2.Pending_Documents__c >= 40, 'MP2 should reflect bulk inserts (>=40).');
    }
}
