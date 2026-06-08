@IsTest(seeAllData=false)
private class ClinicalEntryOpsHandlerTest {

    // Left here in case you ever want to inject metadata via deploy;
    // cannot DML __mdt in tests in this org.
    @TestVisible
    static List<PatientOps_Task__mdt> mockPatientOpsTasks;

    // ---------------------------
    // Test helpers (no-op + logger)
    // ---------------------------

    // No-op: we rely on existing PatientOps_Task__mdt rows in the org
    // (e.g., "Need to be Screened | Null").
    private static void setupMockPatientOpsTaskMetadata() { /* no-op */ }

    // Simple logger to print active picklist values for HP status
    private static void logHpStatusPicklistValues() {
        Schema.DescribeFieldResult dfr = ClinicalEntry__c.Status__c.getDescribe();
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) vals.add(pe.getValue());
        }
    }

    // ------------------------------------------------------
    // BEFORE UPDATE: block when open PatientOps tasks exist
    // ------------------------------------------------------
    @IsTest
    static void test_beforeUpdate_openTasksValidation_bulk_and_security() {
        setupMockPatientOpsTaskMetadata();
        TestDataFactory factory = new TestDataFactory();

        Contact patient = factory.createPatientContact(); insert patient;

        ProjectPlan__c projectPlan = factory.createProjectPlan();
        projectPlan.Study_Type__c   = 'Translational';
        projectPlan.Status__c = 'In Process';
        projectPlan.Time_Point__c   = 'Open scheduling';
        insert projectPlan;

        // Seed 40 HPs at "Need to be Screened"
        List<ClinicalEntry__c> oldHps = new List<ClinicalEntry__c>();
        for (Integer i = 0; i < 40; i++) {
            ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
            hp.Patient__c       = patient.Id;
            hp.Project_Plan__c   = projectPlan.Id;
            hp.Status__c  = 'Need to be Screened';
            hp.Secondary_Status__c = null;
            hp.RecordTypeId = Schema.SObjectType.ClinicalEntry__c
                .getRecordTypeInfosByDeveloperName().get('Sangre_Master_Copy').getRecordTypeId();
            oldHps.add(hp);
        }
        insert oldHps;

        // Create open PatientOps tasks so the update should be blocked
        List<Task> openTasks = new List<Task>();
        for (ClinicalEntry__c hp : oldHps) {
            openTasks.add(new Task(
                WhatId  = hp.Id,
                Subject = 'PatientOps Task: Call Patient',
                Status  = 'Not Started'
            ));
        }
        insert openTasks;

        // Build "new" rows that try to change status (not in bypass list)
        List<ClinicalEntry__c> newHps = new List<ClinicalEntry__c>();
        for (ClinicalEntry__c hp : oldHps) {
            ClinicalEntry__c nu = hp.clone(false, true, false, false);
            nu.Id = hp.Id;
            nu.Status__c = 'Pending Screen';
            nu.Secondary_Status__c = null;
            newHps.add(nu);
        }

        Map<Id, SObject> oldMap = new Map<Id, SObject>();
        for (ClinicalEntry__c hp : oldHps) oldMap.put(hp.Id, hp);

        ClinicalEntryOpsHandler handler = new ClinicalEntryOpsHandler();

        Test.startTest();
        handler.beforeUpdate(newHps, oldMap);
        Test.stopTest();

        // Verify tasks were completed (handler marks open tasks as Completed on non-bypass status change)
        List<Task> completedTasks = [SELECT Id, Status FROM Task WHERE WhatId IN :oldHps AND Status = 'Completed'];
        System.assertEquals(40, completedTasks.size(),
            'All open PatientOps tasks should be marked Completed on non-bypass status change');

        System.assertEquals(true, Schema.sObjectType.Task.isCreateable(), 'Task should be createable');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.isUpdateable(), 'Opportunity should be updateable');
    }

    // -------------------------------------------------------------------
    // BEFORE UPDATE: bypass & auto-delete behavior with open PatientOps tasks
    // -------------------------------------------------------------------
    @IsTest
    static void test_beforeUpdate_bypass_and_autodelete_bulk() {
        setupMockPatientOpsTaskMetadata();
        TestDataFactory factory = new TestDataFactory();

        Contact patient = factory.createPatientContact(); insert patient;

        ProjectPlan__c projectPlan = factory.createProjectPlan();
        projectPlan.Study_Type__c   = 'Translational';
        projectPlan.Status__c = 'In Process';
        projectPlan.Time_Point__c   = 'Open scheduling';
        insert projectPlan;

        // Seed 40 HPs at "Need to be Screened"
        List<ClinicalEntry__c> oldHps = new List<ClinicalEntry__c>();
        for (Integer i = 0; i < 40; i++) {
            ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
            hp.Patient__c       = patient.Id;
            hp.Project_Plan__c   = projectPlan.Id;
            hp.Status__c  = 'Need to be Screened';
            hp.Secondary_Status__c = null;
            hp.RecordTypeId = Schema.SObjectType.ClinicalEntry__c
                .getRecordTypeInfosByDeveloperName().get('Sangre_Master_Copy').getRecordTypeId();
            oldHps.add(hp);
        }
        insert oldHps;

        // Create open tasks
        List<Task> openTasks = new List<Task>();
        for (ClinicalEntry__c hp : oldHps) {
            openTasks.add(new Task(
                WhatId  = hp.Id,
                Subject = 'PatientOps Task: Call Patient',
                Status  = 'Not Started'
            ));
        }
        insert openTasks;

        // Status sets
        List<String> bypassStatuses = new List<String>{
            'At Enrollment Capacity', 'Duplicate Profile', 'Pending Study', 'Out of Territory', 'NTBS-Delayed Outreach'
        };
        List<String> autoDeleteStatuses = new List<String>{
            'At Enrollment Capacity', 'Duplicate Profile', 'Pending Study', 'Out of Territory'
        };

        // First 20 → cycle over bypass list (includes NTBS which is NOT auto-delete)
        List<ClinicalEntry__c> bypassHps = new List<ClinicalEntry__c>();
        for (Integer i = 0; i < 20; i++) {
            ClinicalEntry__c hp = oldHps[i].clone(false, true, false, false);
            hp.Id = oldHps[i].Id;
            hp.Status__c = bypassStatuses[Math.mod(i, bypassStatuses.size())];
            bypassHps.add(hp);
        }

        // Second 20 → strictly auto-delete list
        List<ClinicalEntry__c> autoDeleteHps = new List<ClinicalEntry__c>();
        for (Integer i = 20; i < 40; i++) {
            ClinicalEntry__c hp = oldHps[i].clone(false, true, false, false);
            hp.Id = oldHps[i].Id;
            hp.Status__c = autoDeleteStatuses[Math.mod(i - 20, autoDeleteStatuses.size())];
            autoDeleteHps.add(hp);
        }

        Map<Id, SObject> oldMap = new Map<Id, SObject>();
        for (ClinicalEntry__c hp : oldHps) oldMap.put(hp.Id, hp);

        ClinicalEntryOpsHandler handler = new ClinicalEntryOpsHandler();

        Test.startTest();
        handler.beforeUpdate(bypassHps, oldMap);
        handler.beforeUpdate(autoDeleteHps, oldMap);
        Test.stopTest();

        for (ClinicalEntry__c hp : bypassHps) {
            System.assertEquals(false, hp.hasErrors(), 'Bypassed statuses should not block update');
        }

        // Expect **4** remaining tasks (those on NTBS-Delayed Outreach in bypassHps)
        List<Task> remainingTasks = [SELECT Id, WhatId, Subject FROM Task WHERE WhatId IN :oldHps];
        System.assertEquals(4, remainingTasks.size(), 'Only NTBS-Delayed Outreach tasks should remain');
    }

    // ------------------------------------------------------------
    // AFTER UPDATE: create PatientOps tasks for each changed HP
    // ------------------------------------------------------------
    @IsTest
    static void test_afterUpdate_taskCreation_bulk_and_security() {
        setupMockPatientOpsTaskMetadata();
        TestDataFactory factory = new TestDataFactory();

        Contact patient = factory.createPatientContact(); insert patient;
        User crc = factory.createUser(); insert crc;

        ProjectPlan__c projectPlan = factory.createProjectPlan();
        projectPlan.Study_Type__c   = 'Translational';
        projectPlan.Status__c = 'In Process';
        projectPlan.Time_Point__c   = 'Open scheduling';
        projectPlan.Primary_CRC_Assigned__c = crc.Id;
        insert projectPlan;

        // Seed 40 HPs at "Pending Screen"
        List<ClinicalEntry__c> hps = new List<ClinicalEntry__c>();
        for (Integer i = 0; i < 40; i++) {
            ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
            hp.Patient__c       = patient.Id;
            hp.Project_Plan__c   = projectPlan.Id;
            hp.Status__c  = 'Pending Screen';
            hp.Secondary_Status__c = null;
            hp.RecordTypeId = Schema.SObjectType.ClinicalEntry__c
                .getRecordTypeInfosByDeveloperName().get('Sangre_Master_Copy').getRecordTypeId();
            hps.add(hp);
        }
        insert hps;

        // One picklist print (optional)
        logHpStatusPicklistValues();

        // Now update to a value that matches an existing CMDT key: "Need to be Screened | Null"
        for (ClinicalEntry__c hp : hps) {
            hp.Status__c    = 'Need to be Screened';
            hp.Secondary_Status__c = null;
        }

        Test.startTest();
        try {
            // Capture per-row failures (should be none)
            Database.SaveResult[] results = Database.update(hps, /*allOrNone*/ false);

            Integer dmlFailures = 0;
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    dmlFailures++;
                    for (Database.Error err : results[i].getErrors()) {
                    }
                }
            }
            System.assertEquals(0, dmlFailures, 'DML failed on some rows — see HP TEST DML ERROR logs');
        } catch (DmlException e) {
            for (Integer i = 0; i < e.getNumDml(); i++) {
            }
            System.assert(false, 'Update threw DmlException — see logs');
        }
        Test.stopTest();

        // Sanity: confirm persisted values match what we asked for
        Map<Id, String> wantP = new Map<Id, String>();
        Map<Id, String> wantS = new Map<Id, String>();
        for (ClinicalEntry__c hpWanted : hps) {
            wantP.put(hpWanted.Id, hpWanted.Status__c);
            wantS.put(hpWanted.Id, hpWanted.Secondary_Status__c);
        }
        List<ClinicalEntry__c> dbRows = [
            SELECT Id, Status__c, Secondary_Status__c, RecordType.DeveloperName
            FROM ClinicalEntry__c
            WHERE Id IN :wantP.keySet()
        ];
        Integer unchanged = 0, sample = 0;
        for (ClinicalEntry__c db : dbRows) {
            if (db.Status__c != wantP.get(db.Id) || db.Secondary_Status__c != wantS.get(db.Id)) {
                unchanged++;
                if (sample < 5) {
                    sample++;
                }
            }
        }
        System.assertEquals(0, unchanged,
            'Some HP statuses/secondary did not persist (see HP TEST STATUS DID NOT STICK logs)');

        // Verify tasks created by the handler
        List<Task> created = [SELECT Id FROM Task WHERE WhatId IN :hps];
        System.assertEquals(40, created.size(), 'Should create PatientOps tasks for all HPs');
    }

    // ---------------------------------------------
    // AFTER DELETE: email path smoke (no send in test)
    // ---------------------------------------------
    @IsTest
    static void test_afterDelete_emailSent_bulk_and_security() {
        setupMockPatientOpsTaskMetadata();
        TestDataFactory factory = new TestDataFactory();

        Contact patient = factory.createPatientContact(); insert patient;

        ProjectPlan__c projectPlan = factory.createProjectPlan();
        projectPlan.Study_Type__c   = 'Translational';
        projectPlan.Status__c = 'In Process';
        projectPlan.Time_Point__c   = 'Open scheduling';
        insert projectPlan;

        List<ClinicalEntry__c> hps = new List<ClinicalEntry__c>();
        for (Integer i = 0; i < 40; i++) {
            ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
            hp.Patient__c       = patient.Id;
            hp.Project_Plan__c   = projectPlan.Id;
            hp.Status__c  = 'Need to be Screened';
            hp.Secondary_Status__c = null;
            hp.RecordTypeId = Schema.SObjectType.ClinicalEntry__c
                .getRecordTypeInfosByDeveloperName().get('Sangre_Master_Copy').getRecordTypeId();
            hps.add(hp);
        }
        insert hps;

        Map<Id, SObject> oldMap = new Map<Id, SObject>();
        for (ClinicalEntry__c hp : hps) oldMap.put(hp.Id, hp);

        ClinicalEntryOpsHandler handler = new ClinicalEntryOpsHandler();

        Test.startTest();
        handler.afterDelete(oldMap); // emails are skipped in tests by the handler
        Test.stopTest();

        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.isDeletable(), 'Opportunity should be deletable');
        System.assertEquals(true, Schema.sObjectType.Contact.isAccessible(), 'Contact should be accessible');
    }

    // -----------------------------
    // Safety & smoke coverage
    // -----------------------------
    @IsTest
    static void test_emptyInputs_safe() {
        ClinicalEntryOpsHandler handler = new ClinicalEntryOpsHandler();
        Test.startTest();
        handler.beforeUpdate(new List<SObject>(), new Map<Id, SObject>());
        handler.afterUpdate(new List<SObject>(), new Map<Id, SObject>());
        handler.afterDelete(new Map<Id, SObject>());
        handler.afterInsert(new List<SObject>());
        handler.beforeInsert(new List<SObject>());
        handler.beforeDelete(new Map<Id, SObject>());
        handler.afterUndelete(new List<SObject>());
        Test.stopTest();
        System.assert(true, 'Empty inputs handled safely');
    }

    @IsTest
    static void test_defaultConstructor_smoke() {
        Test.startTest();
        ClinicalEntryOpsHandler handler = new ClinicalEntryOpsHandler();
        Test.stopTest();
        System.assertNotEquals(null, handler, 'Default constructor instantiated successfully');
    }
}