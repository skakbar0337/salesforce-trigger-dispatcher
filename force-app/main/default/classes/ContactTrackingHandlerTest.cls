@IsTest
private class ContactTrackingHandlerTest{

    // Utility: get Contact RT Id by NAME
    private static Id rtId(String name) {
        return Schema.SObjectType.Contact.getRecordTypeInfosByName().get(name).getRecordTypeId();
    }

    // ---------- 1) INSERT: happy path creates CampaignMember ----------
    @IsTest
    static void test_Insert_AddsMember() {
        // Arrange
        Account acc = new Account(Name='A'); insert acc;
        Campaign utm = new Campaign(Name='FB/IG', IsActive=true); insert utm;

        Contact c = new Contact(
            FirstName='T', LastName='P', AccountId=acc.Id,
            RecordTypeId = rtId('Patient'),
            Email='t@example.test', UTM_Campaign__c='FB/IG'
        );
        insert c; // Id is needed inside handler

        // Act: call handler directly
        ContactTrackingHandler h = new ContactTrackingHandler();
        h.afterInsert(new List<SObject>{ c });

        // Assert
        List<CampaignMember> cms = [
            SELECT Id, Status, Campaign.Name
            FROM CampaignMember
            WHERE ContactId = :c.Id AND Campaign.Name='FB/IG'
        ];
        System.assertEquals(1, cms.size(), 'Member should be created');
        System.assertEquals('Responded', cms[0].Status);
    }

    // ---------- 2) UPDATE: separate method so 'firstRun' resets ----------
    @IsTest
    static void test_Update_AddsMember() {
        // Arrange
        Account acc = new Account(Name='A'); insert acc;
        Campaign utm = new Campaign(Name='TT Ads', IsActive=true); insert utm;

        Contact c = new Contact(
            FirstName='U', LastName='P', AccountId=acc.Id,
            RecordTypeId = rtId('Patient'),
            Email='u@example.test', UTM_Campaign__c='TT Ads'
        );
        insert c;

        // Act
        c.Email = 'new@example.test'; update c; // just to mimic a change
        ContactTrackingHandler h = new ContactTrackingHandler();
        h.afterUpdate(new List<SObject>{ c }, new Map<Id,SObject>{ c.Id => c });

        // Assert
        List<CampaignMember> cms = [
            SELECT Id, Status FROM CampaignMember WHERE ContactId=:c.Id
        ];
        System.assertEquals(1, cms.size(), 'Member should be created on update path');
    }

    // ---------- 3) Non-Patient OR blank UTM → no-op ----------
    @IsTest
    static void test_Skips_WhenNotPatientOrBlankUtm() {
        Account acc = new Account(Name='A'); insert acc;

        // Non-patient record type
        Contact nonPatient = new Contact(
            FirstName='X', LastName='Y', AccountId=acc.Id,
            RecordTypeId = rtId('Clinical Staff'),
            Email='x@example.test', UTM_Campaign__c='FB/IG'
        );
        insert nonPatient;

        // Patient but blank UTM
        Contact blankUtm = new Contact(
            FirstName='P', LastName='Z', AccountId=acc.Id,
            RecordTypeId = rtId('Patient'), Email='p@example.test'
        );
        insert blankUtm;

        ContactTrackingHandler h = new ContactTrackingHandler();
        h.afterInsert(new List<SObject>{ nonPatient, blankUtm });

        System.assertEquals(0, [SELECT count() FROM CampaignMember WHERE ContactId IN :new List<Id>{nonPatient.Id, blankUtm.Id}]);
    }

    // ---------- 4) Campaign not found → no member ----------
    @IsTest
    static void test_Skips_WhenCampaignMissing() {
        Account acc = new Account(Name='A'); insert acc;

        Contact c = new Contact(
            FirstName='N', LastName='C', AccountId=acc.Id,
            RecordTypeId = rtId('Patient'),
            Email='n@example.test', UTM_Campaign__c='Does-Not-Exist'
        );
        insert c;

        new ContactTrackingHandler().afterInsert(new List<SObject>{ c });

        System.assertEquals(0, [SELECT count() FROM CampaignMember WHERE ContactId=:c.Id]);
    }

    // ---------- 5) Already a member → avoids duplicate ----------
    @IsTest
    static void test_Skips_WhenAlreadyMember() {
        Account acc = new Account(Name='A'); insert acc;
        Campaign utm = new Campaign(Name='LinkedIn', IsActive=true); insert utm;

        Contact c = new Contact(
            FirstName='A', LastName='M', AccountId=acc.Id,
            RecordTypeId = rtId('Patient'),
            Email='a@example.test', UTM_Campaign__c='LinkedIn'
        );
        insert c;

        // Pre-existing membership
       // insert new CampaignMember(ContactId=c.Id, CampaignId=utm.Id, Status='Responded');

        new ContactTrackingHandler().afterInsert(new List<SObject>{ c });

        // Still exactly one
        System.assertEquals(1, [SELECT count() FROM CampaignMember WHERE ContactId=:c.Id AND CampaignId=:utm.Id]);
    }
}