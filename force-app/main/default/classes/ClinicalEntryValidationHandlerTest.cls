@IsTest
private class ClinicalEntryValidationHandlerTest {

    @TestSetup
    static void setupData() {
        TestDataFactory factory = new TestDataFactory();

        // ---------- Patient for PASS case ----------
        Contact passPatient = factory.createPatientContact();
        insert passPatient;

        // Master Plan for GMP Collection:
        ProjectPlan__c collectionMP = factory.createProjectPlan();
        collectionMP.Study_Type__c = 'Apheresis GMP';
        collectionMP.Aphaeresis_Collection_Type__c = 'Collection';
        insert collectionMP;

        // Master Plan for GMP Screening
        ProjectPlan__c screeningMP = factory.createProjectPlan();
        screeningMP.Study_Type__c = 'Apheresis GMP';
        screeningMP.Aphaeresis_Collection_Type__c = 'Screening';
        insert screeningMP;

        // Recent screening HP (2 days before today) - should pass
        ClinicalEntry__c recentScreening = factory.createHealthPlanOpportunity();
        recentScreening.Patient__c = passPatient.Id;
        recentScreening.Status__c = 'Donated Blood';
        recentScreening.Appointment_Date_Time__c = System.now().addDays(-2);
        recentScreening.Master_Plan__c = screeningMP.Id;
        insert recentScreening;

        // ---------- Patient for FAIL case ----------
        Contact failPatient = factory.createPatientContact();
        failPatient.Email = 'failpatient' + System.now().getTime() + '@test.com';
        failPatient.MobilePhone = '9995551212';
        insert failPatient;

        // Old screening HP (10 days before today) - should fail
        ClinicalEntry__c oldScreening = factory.createHealthPlanOpportunity();
        oldScreening.Patient__c = failPatient.Id;
        oldScreening.Status__c = 'Donated Blood';
        oldScreening.Appointment_Date_Time__c = System.now().addDays(-10);
        oldScreening.Master_Plan__c = screeningMP.Id;
        insert oldScreening;
    }

    @IsTest
    static void testPassesWhenScreeningWithin7Days() {
        TestDataFactory factory = new TestDataFactory();

        Contact patient = [
            SELECT Id FROM Contact
            WHERE Id IN (
                SELECT Patient__c FROM ClinicalEntry__c
                WHERE Status__c = 'Donated Blood'
                AND Appointment_Date_Time__c >= :System.now().addDays(-3)
            )
            LIMIT 1
        ];

        Id collectionMPId = [
            SELECT Id FROM ProjectPlan__c
            WHERE Aphaeresis_Collection_Type__c = 'Collection'
            LIMIT 1
        ].Id;

        ClinicalEntry__c collectionHp = factory.createHealthPlanOpportunity();
        collectionHp.Patient__c = patient.Id;
        collectionHp.Master_Plan__c = collectionMPId;
        collectionHp.Appointment_Date_Time__c = System.now();

        Test.startTest();
        Database.SaveResult sr = Database.insert(collectionHp, false);
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Should not block creation if screening within 7 days');
    }

    @IsTest
    static void testFailsWhenScreeningOlderThan7Days() {
        TestDataFactory factory = new TestDataFactory();

        Contact patient = [
            SELECT Id FROM Contact
            WHERE Id IN (
                SELECT Patient__c FROM ClinicalEntry__c
                WHERE Status__c = 'Donated Blood'
                AND Appointment_Date_Time__c <= :System.now().addDays(-9)
            )
            LIMIT 1
        ];

        Id collectionMPId = [
            SELECT Id FROM ProjectPlan__c
            WHERE Aphaeresis_Collection_Type__c = 'Collection'
            LIMIT 1
        ].Id;

        ClinicalEntry__c collectionHp = factory.createHealthPlanOpportunity();
        collectionHp.Patient__c = patient.Id;
        collectionHp.Master_Plan__c = collectionMPId;
        collectionHp.Appointment_Date_Time__c = System.now();

        Test.startTest();
        Database.SaveResult sr = Database.insert(collectionHp, false);
        Test.stopTest();

        System.assert(!sr.isSuccess(), 'Insert should fail for screening older than 7 days');
        System.assert(sr.getErrors()[0].getMessage().contains('more than 7 days ago'),
            'Error message should indicate screening is too old');
    }

    /**
     * Gate test: afterUpdate should SKIP validation (and SOQL) when Master_Plan__c,
     * Patient__c, and Appointment_Date_Time__c are all unchanged.
     * Mimics Skedulo touching unrelated fields on a GMP Collection HP with stale screening.
     */
    @IsTest
    static void test_afterUpdate_skipsWhenGatedFieldsUnchanged() {
        TestDataFactory factory = new TestDataFactory();

        // Create a Collection HP tied to the fail-patient (10-day-old screening) so it would FAIL
        // if validation ran. Insert via a helper since insert is blocked by validation.
        Contact failPatient = [
            SELECT Id FROM Contact
            WHERE Id IN (
                SELECT Patient__c FROM ClinicalEntry__c
                WHERE Status__c = 'Donated Blood'
                AND Appointment_Date_Time__c <= :System.now().addDays(-9)
            )
            LIMIT 1
        ];
        Id collectionMPId = [SELECT Id FROM ProjectPlan__c WHERE Aphaeresis_Collection_Type__c = 'Collection' LIMIT 1].Id;

        // Build an HP with a safe (non-stale) screening window to allow insert
        // We'll use a different patient with a recent screening for insert to succeed
        Contact safePatient = [
            SELECT Id FROM Contact
            WHERE Id IN (
                SELECT Patient__c FROM ClinicalEntry__c
                WHERE Status__c = 'Donated Blood'
                AND Appointment_Date_Time__c >= :System.now().addDays(-3)
            )
            LIMIT 1
        ];

        ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
        hp.Patient__c = safePatient.Id;
        hp.Master_Plan__c = collectionMPId;
        hp.Appointment_Date_Time__c = System.now();
        insert hp;

        // Now exercise afterUpdate with unchanged gated fields — gate should skip entirely
        Map<Id, ClinicalEntry__c> oldMap = new Map<Id, ClinicalEntry__c>{
            hp.Id => new ClinicalEntry__c(
                Id = hp.Id,
                Master_Plan__c = hp.Master_Plan__c,
                Patient__c = hp.Patient__c,
                Appointment_Date_Time__c = hp.Appointment_Date_Time__c
            )
        };

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        new ClinicalEntryValidationHandler().afterUpdate(new List<ClinicalEntry__c>{ hp }, oldMap);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assertEquals(0, soqlUsed, 'Gate should prevent any SOQL when MP/Patient/Appointment unchanged');
    }

    /**
     * Gate test: afterUpdate should RUN validation when Appointment_Date_Time__c changes.
     */
    @IsTest
    static void test_afterUpdate_runsWhenAppointmentChanged() {
        Id collectionMPId = [SELECT Id FROM ProjectPlan__c WHERE Aphaeresis_Collection_Type__c = 'Collection' LIMIT 1].Id;
        Contact patient = [
            SELECT Id FROM Contact
            WHERE Id IN (
                SELECT Patient__c FROM ClinicalEntry__c
                WHERE Status__c = 'Donated Blood'
                AND Appointment_Date_Time__c >= :System.now().addDays(-3)
            )
            LIMIT 1
        ];

        TestDataFactory factory = new TestDataFactory();
        ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
        hp.Patient__c = patient.Id;
        hp.Master_Plan__c = collectionMPId;
        hp.Appointment_Date_Time__c = System.now();
        insert hp;

        Map<Id, ClinicalEntry__c> oldMap = new Map<Id, ClinicalEntry__c>{
            hp.Id => new ClinicalEntry__c(
                Id = hp.Id,
                Master_Plan__c = hp.Master_Plan__c,
                Patient__c = hp.Patient__c,
                Appointment_Date_Time__c = System.now().addDays(-5) // old value
            )
        };

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        new ClinicalEntryValidationHandler().afterUpdate(new List<ClinicalEntry__c>{ hp }, oldMap);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assert(soqlUsed > 0, 'Validation should run (SOQL fired) when Appointment_Date_Time__c changes');
    }
}