@IsTest
private class ClinicalEntryNameHandlerTest {

    @TestSetup
    static void setupTestData() {
        TestDataFactory factory = new TestDataFactory(); // Instance of factory

        // Create test Contact (Patient)
        Contact patient = factory.createPatientContact();
        insert patient;

        // Create test Health Profile without Name
        ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
        hp.Patient__c = patient.Id;
        insert hp;
    }

    @IsTest
    static void testBeforeInsertSetsName() {
        TestDataFactory factory = new TestDataFactory();

        Contact patient = [SELECT Id, Name FROM Contact LIMIT 1];
        ClinicalEntry__c newHp = factory.createHealthPlanOpportunity();
        newHp.Patient__c = patient.Id;

        Test.startTest();
        insert newHp;
        Test.stopTest();

        ClinicalEntry__c insertedHp = [
            SELECT Name, Patient__c FROM ClinicalEntry__c WHERE Id = :newHp.Id
        ];
        System.assertEquals(patient.Name, insertedHp.Name, 'Name should be set from Patient');
    }

    @IsTest
    static void testBeforeUpdateSetsName() {
        TestDataFactory factory = new TestDataFactory();

        ClinicalEntry__c hp = [
            SELECT Id, Name, Patient__c FROM ClinicalEntry__c LIMIT 1
        ];
        Contact patient = [SELECT Id, Name FROM Contact LIMIT 1];
        hp.Patient__c = patient.Id;
        hp.Name = null;

        Test.startTest();
        update hp;
        Test.stopTest();

        ClinicalEntry__c updatedHp = [
            SELECT Name FROM ClinicalEntry__c WHERE Id = :hp.Id
        ];
        System.assertEquals(patient.Name, updatedHp.Name, 'Updated name should match Patient');
    }

    @IsTest
    static void testNoPatientIdNoChange() {
        TestDataFactory factory = new TestDataFactory();

        ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
        hp.Is_Clone_Originated__c = true;
        insert hp;

        String oldName = hp.Name;
        hp.Name = 'Custom Name';

        Test.startTest();
        update hp;
        Test.stopTest();

        ClinicalEntry__c updatedHp = [
            SELECT Name FROM ClinicalEntry__c WHERE Id = :hp.Id
        ];
        System.assertEquals('Custom Name', updatedHp.Name, 'Name should remain unchanged');
    }

    /**
     * Gate test: beforeUpdate should SKIP the Contact lookup (no SOQL)
     * when Patient__c is unchanged. Mimics Skedulo touching unrelated fields.
     */
    @IsTest
    static void test_beforeUpdate_skipsWhenPatientUnchanged() {
        TestDataFactory factory = new TestDataFactory();
        Contact patient = [SELECT Id, Name FROM Contact LIMIT 1];

        ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
        hp.Patient__c = patient.Id;
        insert hp;

        // Build oldMap with same Patient__c (simulates unrelated-field update)
        Map<Id, ClinicalEntry__c> oldMap = new Map<Id, ClinicalEntry__c>{
            hp.Id => new ClinicalEntry__c(Id = hp.Id, Patient__c = patient.Id)
        };
        List<ClinicalEntry__c> newList = new List<ClinicalEntry__c>{
            new ClinicalEntry__c(Id = hp.Id, Patient__c = patient.Id, Name = 'Pre-set Name')
        };

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        new ClinicalEntryNameHandler().beforeUpdate(newList, oldMap);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assertEquals(0, soqlUsed, 'Gate should prevent any SOQL when Patient__c unchanged');
        System.assertEquals('Pre-set Name', newList[0].Name,
            'Name should not be overwritten when Patient__c unchanged');
    }

    /**
     * Gate test: beforeUpdate should RUN Contact lookup when Patient__c changes.
     */
    @IsTest
    static void test_beforeUpdate_runsWhenPatientChanged() {
        TestDataFactory factory = new TestDataFactory();
        Contact oldPatient = [SELECT Id FROM Contact LIMIT 1];

        Contact newPatient = factory.createPatientContact();
        newPatient.Email = 'newpatient' + System.now().getTime() + '@test.com';
        insert newPatient;
        newPatient = [SELECT Id, Name FROM Contact WHERE Id = :newPatient.Id];

        ClinicalEntry__c hp = factory.createHealthPlanOpportunity();
        hp.Patient__c = oldPatient.Id;
        insert hp;

        Map<Id, ClinicalEntry__c> oldMap = new Map<Id, ClinicalEntry__c>{
            hp.Id => new ClinicalEntry__c(Id = hp.Id, Patient__c = oldPatient.Id)
        };
        List<ClinicalEntry__c> newList = new List<ClinicalEntry__c>{
            new ClinicalEntry__c(Id = hp.Id, Patient__c = newPatient.Id)
        };

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        new ClinicalEntryNameHandler().beforeUpdate(newList, oldMap);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Test.stopTest();

        System.assert(soqlUsed > 0, 'Contact lookup should run (SOQL fired) when Patient__c changes');
        System.assertEquals(newPatient.Name, newList[0].Name,
            'Name should be set from new Patient when Patient__c changes');
    }
}