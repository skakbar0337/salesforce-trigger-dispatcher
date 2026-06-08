@IsTest
private class ClinicalEntryContactHandlerTest {

    // ---------------------------------------------------
    // Test Setup
    // ---------------------------------------------------
    @testSetup
    static void setupData() {
        TestDataFactory f = new TestDataFactory();
        insert new Account(Name = 'Test Account', Type = 'Customer', Industry = 'Healthcare');

        Contact patient = f.createPatientContact();
        Contact advocate = f.createResearchCoordinator();
        insert new List<Contact>{ patient, advocate };
    }

    // ---------------------------------------------------
    // Helpers
    // ---------------------------------------------------
    private static Map<String, Contact> getActors() {
        Map<String, Contact> out = new Map<String, Contact>();
        List<Contact> cs = [
            SELECT Id, ICF_Version__c, Most_recent_completed_SO_date__c, Email
            FROM Contact
            ORDER BY CreatedDate ASC
            LIMIT 2
        ];
        System.assertEquals(2, cs.size(), 'Expected two contacts from @testSetup.');
        out.put('patient', cs[0]);   // first inserted = patient
        out.put('advocate', cs[1]);  // second inserted = advocate
        return out;
    }

    /**
     * Build & insert a single Health Profile with supplied values.
     * Ensures unique Name to sidestep duplicate rules.
     */
    private static ClinicalEntry__c makeHp(
        Contact patient,
        Contact advocate,
        Date icfDate,
        String icfVersion,
        Datetime apptDt,
        Integer vol
    ) {
        TestDataFactory f = new TestDataFactory();
        ClinicalEntry__c hp = f.createHealthPlanOpportunity();
        hp.Patient__c = (patient != null) ? patient.Id : null;
        hp.Patient_Advocate__c = (advocate != null) ? advocate.Id : null;
        hp.ICF_Date_of_Signature__c = icfDate;
        hp.ICF_Version_on_File__c   = icfVersion;
        hp.Appointment_Date_Time__c = apptDt;                     // dummy appointment
        hp.Requested_Volume_mL_On_site__c = vol;
        hp.Name = 'HP-' + String.valueOf(Crypto.getRandomInteger()); // unique name
        insert hp;
        return hp;
    }

    /**
     * Build (but DO NOT insert) a Health Profile record to use in bulk insert.
     */
    private static ClinicalEntry__c buildHpRecordWithoutInsert(
        TestDataFactory f,
        Id patientId,
        Id advocateId,
        Date icfDate,
        String icfVersion,
        Datetime apptDt,
        Integer vol,
        Integer seqForUniqueness
    ) {
        ClinicalEntry__c hp = f.createHealthPlanOpportunity(); // returns unsaved SObject
        hp.Patient__c = patientId;
        hp.Patient_Advocate__c = advocateId;
        hp.ICF_Date_of_Signature__c = icfDate;
        hp.ICF_Version_on_File__c   = icfVersion;
        hp.Appointment_Date_Time__c = apptDt;
        hp.Requested_Volume_mL_On_site__c = vol;
        hp.Name = 'HP-BULK-' + seqForUniqueness + '-' + String.valueOf(System.now().getTime());
        return hp;
    }

    /**
     * Insert a Completed Specimen Order for the given HP.
     * SO.Appointment_Date_Time__c is a **formula** (HP->Appointment),
     * so we first set HP.Appointment_Date_Time__c to the desired value.
     */
    private static WorkRequest__c makeCompletedSO(Id hpId, Id mpId, Datetime apptDt) {
        ClinicalEntry__c hpToUpdate = [
            SELECT Appointment_Date_Time__c
            FROM ClinicalEntry__c
            WHERE Id = :hpId
            LIMIT 1
        ];
        hpToUpdate.Appointment_Date_Time__c = apptDt;
        update hpToUpdate;

        TestDataFactory f = new TestDataFactory();
        WorkRequest__c so = f.createPurchaseOrder(hpId, mpId, 'Complete');
        insert so; // formula on SO will now reflect HP's appointment
        return so;
    }

    // ---------------------------------------------------
    // Tests
    // ---------------------------------------------------

    /**
     * afterInsert:
     * - Patient ICF_Version__c aggregated from related HP(s)
     * - Advocate Most_recent_completed_SO_date__c reflects latest Completed SO date
     */
    @IsTest
    static void test_afterInsert_updatesPatientAndAdvocate() {
        // ---- CRUD/FLS checks ----
        System.assertEquals(true, Schema.sObjectType.ProjectPlan__c.isCreateable(), 'User must create Master Plan.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.isCreateable(), 'User must create Health Profile.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.Patient__c.isUpdateable(), 'Need FLS to set Patient__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.Patient_Advocate__c.isUpdateable(), 'Need FLS to set Patient_Advocate__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.ICF_Version_on_File__c.isUpdateable(), 'Need FLS to set ICF_Version_on_File__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.ICF_Date_of_Signature__c.isUpdateable(), 'Need FLS to set ICF_Date_of_Signature__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.Appointment_Date_Time__c.isUpdateable(), 'Need FLS to set Appointment_Date_Time__c.');
        System.assertEquals(true, Schema.sObjectType.Contact.fields.ICF_Version__c.isUpdateable(), 'Need FLS to update Contact.ICF_Version__c.');
        System.assertEquals(true, Schema.sObjectType.Contact.fields.Most_recent_completed_SO_date__c.isUpdateable(), 'Need FLS to update Contact.Most_recent_completed_SO_date__c.');
        System.assertEquals(true, Schema.sObjectType.WorkRequest__c.isCreateable(), 'User must create Purchase Order.');

        Test.startTest();
        Map<String, Contact> actors = getActors();
        Contact patient  = actors.get('patient');
        Contact advocate = actors.get('advocate');

        TestDataFactory f = new TestDataFactory();
        ProjectPlan__c mp;
        try {
            mp = f.createProjectPlan();
            insert mp;
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception inserting Master Plan: ' + e.getMessage());
        }

        Datetime hpAppt = System.now().addDays(-5);
        ClinicalEntry__c hp;
        try {
            hp = makeHp(
                patient, advocate,
                Date.today().addDays(-10),
                'SAN-BB-01 v4.0',
                hpAppt,
                100
            );
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception creating Health Profile: ' + e.getMessage());
        }

        // Create Completed SO with desired appointment (drives advocate rollup)
        Datetime soWhen = System.now().addDays(-3);
        try {
            makeCompletedSO(hp.Id, mp.Id, soWhen);
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception creating Completed SO: ' + e.getMessage());
        }

        try {
            ClinicalEntryContactHandler handler = new ClinicalEntryContactHandler();
            handler.afterInsert(new List<SObject>{ hp });
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception in afterInsert handler: ' + e.getMessage());
        }

        Contact[] reloaded = [
            SELECT Id, ICF_Version__c, Most_recent_completed_SO_date__c
            FROM Contact
            WHERE Id IN :new Set<Id>{ patient.Id, advocate.Id }
        ];
        Map<Id, Contact> byId = new Map<Id, Contact>(reloaded);

        System.assert(byId.get(patient.Id).ICF_Version__c != null,
                      'Patient ICF_Version__c should be populated.');
        System.assert(byId.get(patient.Id).ICF_Version__c.contains('SAN-BB-01 v4.0'),
                      'ICF_Version__c should include the HP ICF version.');
        System.assertEquals(soWhen, byId.get(advocate.Id).Most_recent_completed_SO_date__c,
                            'Advocate should get the latest completed SO appointment date.');
        Test.stopTest();
    }

    /**
     * afterUpdate:
     * - Patient changed A -> B (both updated)
     * - ICF/version/date changed
     * - appt/vol change also considered
     */
    @IsTest
    static void test_afterUpdate_patientChange_updatesOldAndNewPatients() {
        // ---- CRUD/FLS checks ----
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.isUpdateable(), 'User must update Health Profile.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.Patient__c.isUpdateable(), 'Need FLS to change Patient__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.ICF_Version_on_File__c.isUpdateable(), 'Need FLS to change ICF_Version_on_File__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.ICF_Date_of_Signature__c.isUpdateable(), 'Need FLS to change ICF_Date_of_Signature__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.Appointment_Date_Time__c.isUpdateable(), 'Need FLS to change Appointment_Date_Time__c.');
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.fields.Requested_Volume_mL_On_site__c.isUpdateable(), 'Need FLS to change Requested_Volume_mL_On_site__c.');
        System.assertEquals(true, Schema.sObjectType.Contact.fields.ICF_Version__c.isUpdateable(), 'Need FLS to update Contact.ICF_Version__c.');

        Test.startTest();
        Map<String, Contact> actors = getActors();
        Contact patientA  = actors.get('patient');
        Contact advocate  = actors.get('advocate');

        TestDataFactory f = new TestDataFactory();
        Contact patientB = f.createPatientContact();
        patientB.Email = 'patientb' + System.now().getTime() + '@test.com';
        patientB.MobilePhone = '9995551213';
        try {
            insert patientB;
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception inserting patientB: ' + e.getMessage());
        }

        ClinicalEntry__c hp;
        try {
            hp = makeHp(
                patientA, advocate,
                Date.today().addDays(-20),
                'ICF v1',
                System.now().addDays(-10),
                50
            );
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception creating initial Health Profile: ' + e.getMessage());
            return; // defensive
        }

        // Snapshot for oldMap
        ClinicalEntry__c oldHp = hp.clone(false, true, false, false);

        // Change patient + ICF + appt/vol
        hp.Patient__c = patientB.Id;
        hp.ICF_Version_on_File__c = 'ICF v2';
        hp.ICF_Date_of_Signature__c = Date.today().addDays(-5);
        hp.Appointment_Date_Time__c = System.now().addDays(-2);
        hp.Requested_Volume_mL_On_site__c = 150;

        try {
            update hp;
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception updating Health Profile: ' + e.getMessage());
        }

        try {
            ClinicalEntryContactHandler handler = new ClinicalEntryContactHandler();
            Map<Id, SObject> oldMap = new Map<Id, SObject>{ oldHp.Id => oldHp };
            handler.afterUpdate(new List<SObject>{ hp }, oldMap);
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception in afterUpdate handler: ' + e.getMessage());
        }
        Test.stopTest();

        List<Contact> refreshed = [
            SELECT Id, ICF_Version__c
            FROM Contact
            WHERE Id IN :new Set<Id>{ patientA.Id, patientB.Id }
        ];
        Map<Id, Contact> byId = new Map<Id, Contact>(refreshed);

        System.assert(byId.get(patientA.Id).ICF_Version__c != null,
                      'Old patient should still have ICF_Version__c populated.');
        System.assert(byId.get(patientB.Id).ICF_Version__c != null,
                      'New patient should get ICF_Version__c populated.');
        System.assert(byId.get(patientB.Id).ICF_Version__c.contains('ICF v2'),
                      'New patient should include latest ICF version text.');
    }

    /**
     * afterDelete:
     * - Keep one HP (hpKeep) for the advocate and tie the SO to it.
     * - Delete another HP (hpDelete) for the same advocate.
     * - Handler uses existing HPs to map advocate → HP, so the rollup should still work.
     */
    @IsTest
    static void test_afterDelete_advocateUpdated() {
        // ---- CRUD/FLS checks ----
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.isDeletable(), 'User must delete Health Profile.');
        System.assertEquals(true, Schema.sObjectType.Contact.fields.Most_recent_completed_SO_date__c.isUpdateable(), 'Need FLS to update Contact.Most_recent_completed_SO_date__c.');
        System.assertEquals(true, Schema.sObjectType.ProjectPlan__c.isCreateable(), 'User must create Master Plan.');
        System.assertEquals(true, Schema.sObjectType.WorkRequest__c.isCreateable(), 'User must create Purchase Order.');

        Test.startTest();
        Map<String, Contact> actors = getActors();
        Contact patient  = actors.get('patient');
        Contact advocate = actors.get('advocate');

        TestDataFactory f = new TestDataFactory();
        ProjectPlan__c mp;
        try {
            mp = f.createProjectPlan();
            insert mp;
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception inserting Master Plan: ' + e.getMessage());
        }

        // HP we KEEP (used for SO rollup)
        ClinicalEntry__c hpKeep;
        try {
            hpKeep = makeHp(
                patient, advocate,
                Date.today().addDays(-15),
                'ICF vKeep',
                System.now().addDays(-12),
                110
            );
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception creating hpKeep: ' + e.getMessage());
            return;
        }

        // HP we DELETE (same advocate)
        ClinicalEntry__c hpDelete;
        try {
            hpDelete = makeHp(
                patient, advocate,
                Date.today().addDays(-14),
                'ICF vDel',
                System.now().addDays(-11),
                120
            );
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception creating hpDelete: ' + e.getMessage());
            return;
        }

        // Completed SO tied to hpKeep
        Datetime soWhen = System.now().addDays(-1);
        try {
            makeCompletedSO(hpKeep.Id, mp.Id, soWhen);
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception creating Completed SO: ' + e.getMessage());
        }

        // Delete the other HP and invoke handler.afterDelete
        Map<Id, SObject> oldMap = new Map<Id, SObject>{ hpDelete.Id => hpDelete };
        try {
            delete hpDelete;
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception deleting hpDelete: ' + e.getMessage());
        }

        try {
            ClinicalEntryContactHandler handler = new ClinicalEntryContactHandler();
            handler.afterDelete(oldMap);
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception in afterDelete handler: ' + e.getMessage());
        }

        Contact adv = [
            SELECT Id, Most_recent_completed_SO_date__c
            FROM Contact
            WHERE Id = :advocate.Id
            LIMIT 1
        ];
        System.assertEquals(soWhen, adv.Most_recent_completed_SO_date__c,
                            'Advocate date should reflect latest completed SO even when another HP was deleted.');
        Test.stopTest();
    }

    /**
     * Bulk insert (100 HPs):
     * - Build 100 HPs in memory and perform a single bulk insert to avoid SOQL/CPU hits from other triggers.
     * - Then invoke our handler directly on those records.
     */
    @IsTest
    static void test_bulk_afterInsert_200plus() {
        // ---- CRUD/FLS checks ----
        System.assertEquals(true, Schema.sObjectType.ClinicalEntry__c.isCreateable(), 'User must create Health Profiles in bulk.');
        System.assertEquals(true, Schema.sObjectType.Contact.fields.ICF_Version__c.isUpdateable(), 'Need FLS to update Contact.ICF_Version__c.');

        TestDataFactory f = new TestDataFactory();

        // Create unique patients & advocates to avoid duplicate rules
        List<Contact> patients = new List<Contact>();
        List<Contact> advocates = new List<Contact>();

        for (Integer i = 0; i < 5; i++) {
            Contact c = f.createPatientContact();
            c.Email = 'p' + i + '_' + System.now().getTime() + '@bulk.test';
            c.MobilePhone = '70000' + String.valueOf(1000 + i);
            patients.add(c);
        }
        for (Integer i = 0; i < 5; i++) {
            Contact c = f.createResearchCoordinator();
            c.Email = 'a' + i + '_' + System.now().getTime() + '@bulk.test';
            c.MobilePhone = '80000' + String.valueOf(1000 + i);
            advocates.add(c);
        }
        try {
            insert patients;
            insert advocates;
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception inserting contacts: ' + e.getMessage());
        }

        // Build 100 HPs (do not insert per-record)
        Integer BULK_COUNT = 100; // reduced to avoid CPU limit from other org triggers
        List<ClinicalEntry__c> toInsert = new List<ClinicalEntry__c>();
        Date baseDate = Date.today().addDays(-30);
        Datetime baseDt = System.now().addDays(-30);

        for (Integer i = 0; i < BULK_COUNT; i++) {
            Integer pIdx = Math.mod(i, patients.size());
            Integer aIdx = Math.mod(i, advocates.size());
            toInsert.add(
                buildHpRecordWithoutInsert(
                    f,
                    patients[pIdx].Id,
                    advocates[aIdx].Id,
                    baseDate.addDays(i),
                    'ICF-Bulk-' + i,
                    baseDt.addDays(i),
                    50 + i,
                    i
                )
            );
        }

        Test.startTest();
        try {
            insert toInsert;  // fires other triggers once in a bulk context
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception inserting bulk HPs: ' + e.getMessage());
        }

        // Exercise our handler directly on the same records
        try {
            ClinicalEntryContactHandler handler = new ClinicalEntryContactHandler();
            List<SObject> arg = new List<SObject>(); arg.addAll(toInsert);
            handler.afterInsert(arg);
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception in bulk afterInsert handler: ' + e.getMessage());
        }
        Test.stopTest();

        // Spot check: first patient should have ICF_Version__c set
        Contact check = [
            SELECT Id, ICF_Version__c
            FROM Contact
            WHERE Id = :patients[0].Id
            LIMIT 1
        ];
        System.assert(check.ICF_Version__c != null,
                      'Bulk run should still update patient ICF_Version__c.');
    }
}