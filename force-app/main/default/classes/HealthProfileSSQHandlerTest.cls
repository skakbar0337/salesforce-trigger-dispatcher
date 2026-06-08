@IsTest
private class HealthProfileSSQHandlerTest {

    // ---------------------------
    // Helper: picklist resolvers
    // ---------------------------

    /** First available value from SSQ # picklist (required on SSQ object). */
    private static String firstSsqNumber() {
        Schema.DescribeFieldResult dfr =
            Study_Specific_Question__c.Study_Specific_Question__c.getDescribe();
        List<Schema.PicklistEntry> entries = dfr.getPicklistValues();
        System.assert(entries.size() > 0, 'No values found for SSQ # picklist.');
        return entries[0].getValue();
    }

    /** First available value from SSDNQ # picklist (may be optional in some orgs). */
    private static String firstSsdnqNumberOrNull() {
        Schema.DescribeFieldResult dfr =
            Study_Specific_DNQ_Question__c.SSDNQ_No__c.getDescribe();
        List<Schema.PicklistEntry> entries = dfr.getPicklistValues();
        return entries.isEmpty() ? null : entries[0].getValue();
    }

    // ---------------------------
    // Test data builders
    // ---------------------------

    /** Create N SSQ records for a Master Plan (sets required SSQ #). */
    private static List<Study_Specific_Question__c> makeSsqs(Id masterPlanId, Integer n) {
        String ssqNo = firstSsqNumber();
        List<Study_Specific_Question__c> out = new List<Study_Specific_Question__c>();
        for (Integer i = 0; i < n; i++) {
            out.add(new Study_Specific_Question__c(
                Master_Plan__c             = masterPlanId,
                Question__c                = 'SSQ Q' + i,
                Study_Specific_Question__c = ssqNo
            ));
        }
        insert out;
        return out;
    }

    /** Create N DNQ Question records for a Master Plan (sets SSDNQ # if present). */
    private static List<Study_Specific_DNQ_Question__c> makeDnqs(Id masterPlanId, Integer n) {
        String dnqNo = firstSsdnqNumberOrNull();
        List<Study_Specific_DNQ_Question__c> out = new List<Study_Specific_DNQ_Question__c>();
        for (Integer i = 0; i < n; i++) {
            Study_Specific_DNQ_Question__c rec = new Study_Specific_DNQ_Question__c(
                Master_Plan__c  = masterPlanId,
                DNQ_Question__c = 'DNQ Q' + i
            );
            if (dnqNo != null) rec.SSDNQ_No__c = dnqNo;
            out.add(rec);
        }
        insert out;
        return out;
    }

    /** Build (not insert) N Health Profiles for a Master Plan; allow setting the Skip flag. */
    private static List<HealthProfile__c> buildHealthProfiles(Id mpId, Integer n, Boolean setSkip) {
        TestDataFactory f = new TestDataFactory();
        List<HealthProfile__c> hps = new List<HealthProfile__c>();
        for (Integer i = 0; i < n; i++) {
            HealthProfile__c hp = f.createHealthPlanOpportunity();
            hp.Master_Plan__c = mpId;
            hp.Skip_SSQ_Creation__c = setSkip;
            hp.Is_Clone_Originated__c = true;
            hps.add(hp);
        }
        return hps;
    }

    /** Insert HPs and re-query minimal fields. */
    private static List<HealthProfile__c> insertHps(List<HealthProfile__c> toInsert) {
        insert toInsert;
        return [
            SELECT Id, Master_Plan__c, Skip_SSQ_Creation__c
            FROM HealthProfile__c
            WHERE Id IN :toInsert
        ];
    }

    // ---------------------------
    // Tests
    // ---------------------------

    /**
     * Bulk path: afterInsert creates SSQ & DNQ answers, afterUpdate is idempotent (no duplicates).
     *  - 10 HPs, 5 SSQs, 3 DNQs → expect 50 SSQ answers and 30 DNQ answers.
     */
    @IsTest
    static void test_afterInsert_and_afterUpdate_bulk_idempotent() {
        TestDataFactory f = new TestDataFactory();
        MasterPlan__c mp = f.createMasterPlan(); insert mp;
        makeSsqs(mp.Id, 5);
        makeDnqs(mp.Id, 3);

        List<HealthProfile__c> pending = buildHealthProfiles(mp.Id, 10, false);

            Test.startTest();

            List<HealthProfile__c> inserted = insertHps(pending);

            HealthProfileSSQHandler h = new HealthProfileSSQHandler();

            // afterInsert
            List<SObject> scope = new List<SObject>();
            for (HealthProfile__c r : inserted) scope.add(r);
            h.afterInsert(scope);

            // afterUpdate (idempotent)
            h.afterUpdate(scope, new Map<Id,SObject>());

            Test.stopTest();

        Integer ssqCount = [SELECT COUNT() FROM Study_Specific_Answer__c WHERE Health_Profile__c IN :pending];
        Integer dnqCount = [SELECT COUNT() FROM Study_Specific_DNQ_Answer__c WHERE Health_Profile__c IN :pending];

        System.assertEquals(10 * 5, ssqCount, 'Expected 5 SSQ answers per HP for 10 HPs.');
        System.assertEquals(10 * 3, dnqCount, 'Expected 3 DNQ answers per HP for 10 HPs.');
    }

    /**
     * Single-record path: answers are created; second run does not add duplicates.
     */
    @IsTest
    static void test_singleRecord_creation_and_idempotency() {
        TestDataFactory f = new TestDataFactory();
        MasterPlan__c mp = f.createMasterPlan();
        insert mp;

        List<Study_Specific_Question__c> ssqs = makeSsqs(mp.Id, 4);
        makeDnqs(mp.Id, 1);

        // Build one HP (not inserted yet) and ensure Skip flag is FALSE
        HealthProfile__c hp = f.createHealthPlanOpportunity();
        hp.Master_Plan__c = mp.Id;
        hp.Skip_SSQ_Creation__c = false;
        hp.Is_Clone_Originated__c = true;

            // Insert and requery as typed list
            List<HealthProfile__c> inserted =
                insertHps(new List<HealthProfile__c>{ hp });
            System.assertEquals(1, inserted.size(), 'Expected one HP inserted.');
            hp = inserted[0];

            // Build scope as typed records, then upcast
            List<HealthProfile__c> typedScope =
                [SELECT Id, Master_Plan__c, Skip_SSQ_Creation__c
                 FROM HealthProfile__c WHERE Id = :hp.Id];

            List<SObject> scope = new List<SObject>();
            scope.addAll(typedScope);

            Test.startTest();
            HealthProfileSSQHandler h = new HealthProfileSSQHandler();
            h.afterInsert(scope);
            h.afterUpdate(scope, new Map<Id,SObject>()); // idempotency
            Test.stopTest();

            Integer postSsq = [SELECT COUNT() FROM Study_Specific_Answer__c WHERE Health_Profile__c = :hp.Id];
            Integer postDnq = [SELECT COUNT() FROM Study_Specific_DNQ_Answer__c WHERE Health_Profile__c = :hp.Id];

            System.assertEquals(ssqs.size(), postSsq,
                'One SSQ answer per SSQ question; no duplicates.');
            System.assertEquals(1, postDnq,
                'One DNQ answer for one DNQ question.');
    }

    /**
     * Skip flag and missing Master Plan: handler should do nothing.
     */
    @IsTest
    static void test_respectsSkipFlag_and_handlesMissingMasterPlan() {
        TestDataFactory f = new TestDataFactory();
        MasterPlan__c mp = f.createMasterPlan(); insert mp;
        makeSsqs(mp.Id, 2);
        makeDnqs(mp.Id, 2);

        // HP with Skip flag = TRUE (should be ignored)
        HealthProfile__c hpSkip = f.createHealthPlanOpportunity();
        hpSkip.Master_Plan__c = mp.Id;
        hpSkip.Skip_SSQ_Creation__c = true;
        hpSkip.Is_Clone_Originated__c = true;

        // HP without a Master Plan (should be ignored)
        HealthProfile__c hpNoMp = f.createHealthPlanOpportunity();
        hpNoMp.Master_Plan__c = null;
        hpNoMp.Is_Clone_Originated__c = true;

            insert new List<HealthProfile__c>{ hpSkip, hpNoMp };

            // Build scope via typed query and then upcast
            List<HealthProfile__c> typedScope =
                [SELECT Id, Master_Plan__c, Skip_SSQ_Creation__c
                 FROM HealthProfile__c
                 WHERE Id IN :new List<Id>{ hpSkip.Id, hpNoMp.Id }];

            List<SObject> scope = new List<SObject>();
            scope.addAll(typedScope);

            Test.startTest();
            HealthProfileSSQHandler h = new HealthProfileSSQHandler();
            h.afterInsert(scope);
            Test.stopTest();

        Integer ssq = [SELECT COUNT()
                       FROM Study_Specific_Answer__c
                       WHERE Health_Profile__c IN :new List<Id>{ hpSkip.Id, hpNoMp.Id }];
        Integer dnq = [SELECT COUNT()
                       FROM Study_Specific_DNQ_Answer__c
                       WHERE Health_Profile__c IN :new List<Id>{ hpSkip.Id, hpNoMp.Id }];

        System.assertEquals(0, ssq, 'Skip flag or missing MP should create zero SSQ answers.');
        System.assertEquals(0, dnq, 'Skip flag or missing MP should create zero DNQ answers.');
    }

    /**
     * Gate test: afterUpdate should SKIP SSQ/DNQ work (no SOQL, no new rows)
     * when Master_Plan__c and Skip_SSQ_Creation__c are unchanged.
     * This is the Skedulo-bulk-save scenario (only unrelated fields touched).
     */
    @IsTest
    static void test_afterUpdate_skipsWhenMasterPlanUnchanged() {
        TestDataFactory f = new TestDataFactory();
        MasterPlan__c mp = f.createMasterPlan(); insert mp;
        makeSsqs(mp.Id, 3);
        makeDnqs(mp.Id, 2);

        // Insert 5 HPs -> afterInsert creates answers
        List<HealthProfile__c> pending = buildHealthProfiles(mp.Id, 5, false);
        insert pending;

        // Delete all generated answers so we can detect if gate lets the handler re-create them
        delete [SELECT Id FROM Study_Specific_Answer__c WHERE Health_Profile__c IN :pending];
        delete [SELECT Id FROM Study_Specific_DNQ_Answer__c WHERE Health_Profile__c IN :pending];

        // Build a matching oldMap with identical MP and Skip flag (simulates unrelated-field update)
        Map<Id, HealthProfile__c> oldMap = new Map<Id, HealthProfile__c>();
        List<HealthProfile__c> newList = [SELECT Id, Master_Plan__c, Skip_SSQ_Creation__c FROM HealthProfile__c WHERE Id IN :pending];
        for (HealthProfile__c hp : newList) {
            oldMap.put(hp.Id, new HealthProfile__c(
                Id = hp.Id,
                Master_Plan__c = hp.Master_Plan__c,
                Skip_SSQ_Creation__c = hp.Skip_SSQ_Creation__c
            ));
        }

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        new HealthProfileSSQHandler().afterUpdate(newList, oldMap);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assertEquals(0, soqlUsed, 'Gate should prevent any SOQL when MP/Skip unchanged');
        System.assertEquals(0, [SELECT COUNT() FROM Study_Specific_Answer__c WHERE Health_Profile__c IN :pending],
            'No SSQ answers should be re-created when MP unchanged');
        System.assertEquals(0, [SELECT COUNT() FROM Study_Specific_DNQ_Answer__c WHERE Health_Profile__c IN :pending],
            'No DNQ answers should be re-created when MP unchanged');
    }

    /**
     * Gate test: afterUpdate should RUN SSQ work when Master_Plan__c changes.
     */
    @IsTest
    static void test_afterUpdate_runsWhenMasterPlanChanged() {
        TestDataFactory f = new TestDataFactory();
        MasterPlan__c mp1 = f.createMasterPlan(); insert mp1;
        MasterPlan__c mp2 = f.createMasterPlan(); insert mp2;
        makeSsqs(mp2.Id, 2);

        List<HealthProfile__c> pending = buildHealthProfiles(mp1.Id, 3, false);
        insert pending;

        // Simulate MP reassignment from mp1 -> mp2
        Map<Id, HealthProfile__c> oldMap = new Map<Id, HealthProfile__c>();
        for (HealthProfile__c hp : pending) {
            oldMap.put(hp.Id, new HealthProfile__c(Id = hp.Id, Master_Plan__c = mp1.Id, Skip_SSQ_Creation__c = false));
            hp.Master_Plan__c = mp2.Id;
        }

        Test.startTest();
        new HealthProfileSSQHandler().afterUpdate(pending, oldMap);
        Test.stopTest();

        Integer ssqForMp2 = [SELECT COUNT() FROM Study_Specific_Answer__c WHERE Health_Profile__c IN :pending];
        System.assert(ssqForMp2 > 0, 'SSQ answers should be created when MP changes');
    }
}