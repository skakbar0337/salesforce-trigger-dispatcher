@IsTest
private class ContactPatientIDHandlerTest {

    @TestSetup
    static void setupSeedData() {
        // Seed record with numeric PID to test fallback handler
        Contact numeric = new Contact(
            FirstName = 'Seed2',
            LastName = 'Numeric',
            Identity__c = 'Patient',
            Diagnosis__c = 'Unknown',
            Patient_ID_New__c = '160005',
            RecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Patient').getRecordTypeId()
        );
        insert numeric;
    }

    @IsTest
    static void testFallbackNumericPIDAssignment() {
        Contact contact = new Contact(
            FirstName = 'Fallback',
            LastName = 'Numeric',
            Identity__c = 'Patient',
            Diagnosis__c = 'Unknown',
            RecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Patient').getRecordTypeId()
        );

        insert contact;

        Contact result = [SELECT Patient_ID_New__c FROM Contact WHERE Id = :contact.Id];
        System.assert(Pattern.matches('\\d{6}', result.Patient_ID_New__c),
            'Fallback PID format invalid: ' + result.Patient_ID_New__c);
    }

    @IsTest
    static void testNonPatientIdentityDoesNotAssignID() {
        Contact contact = new Contact(
            FirstName = 'NonPatient',
            LastName = 'Contact',
            Identity__c = 'Scientist',
            Diagnosis__c = 'Lymphoma'
        );

        insert contact;

        Contact result = [SELECT Patient_ID_New__c FROM Contact WHERE Id = :contact.Id];
        System.assertEquals(null, result.Patient_ID_New__c, 'Non-patient should not receive a PID');
    }

    @IsTest
    static void testNoDuplicatePIDForBulkInsert() {
        List<Contact> contacts = new List<Contact>();

        for (Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(
                FirstName = 'Bulk' + i,
                LastName = 'Patient',
                Identity__c = 'Patient',
                Diagnosis__c = 'Unknown',
                RecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByName().get('Patient').getRecordTypeId()
            ));
        }

        insert contacts;

        List<Contact> inserted = [SELECT Patient_ID_New__c FROM Contact WHERE Id IN :contacts];
        Set<String> ids = new Set<String>();

        for (Contact c : inserted) {
            System.assert(Pattern.matches('\\d{6}', c.Patient_ID_New__c),
                'Invalid format: ' + c.Patient_ID_New__c);
            System.assert(!ids.contains(c.Patient_ID_New__c),
                'Duplicate PID found: ' + c.Patient_ID_New__c);
            ids.add(c.Patient_ID_New__c);
        }
    }
}