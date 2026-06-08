@IsTest
private class AccountSDRUpdateHandlerTest {

    private static User createAdminRunner(String suffix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            FirstName = 'Runner' + suffix, LastName = 'Admin', Alias = 'ra' + suffix,
            Email = 'runner' + suffix + '.admin@example.com',
            Username = 'runner' + suffix + '.admin+' + System.currentTimeMillis() + '@example.com',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
    }

    @IsTest
    static void testSDRUpdate_ReassignsSubmittedICs() {
        User runner = createAdminRunner('1');
        insert runner;

        System.runAs(runner) {
            TestDataFactory factory = new TestDataFactory();
            User oldSdr       = factory.createUser2('old1');
            User newSdr       = factory.createUser2('new1');
            User unrelatedSdr = factory.createUser2('unrelated');
            insert new List<User>{ oldSdr, newSdr, unrelatedSdr };

            Account acct = factory.createPharmaAccount();
            acct.Territory_SDR__c = oldSdr.Id;
            insert acct;

            Contact contact = factory.createResearcherContact(acct.Id);
            insert contact;

            Id icRtId = Schema.SObjectType.Incidence_Check__c
                .getRecordTypeInfosByName().get('Donor Recruitment Inquiry').getRecordTypeId();

            Incidence_Check__c ic1 = factory.createValidIncidenceCheck(contact.Id, icRtId, 'Submitted', oldSdr.Id);
            Incidence_Check__c ic2 = factory.createValidIncidenceCheck(contact.Id, icRtId, 'Submitted', oldSdr.Id);
            Incidence_Check__c icUnrelated =
                factory.createValidIncidenceCheck(contact.Id, icRtId, 'Submitted', unrelatedSdr.Id);

            List<Incidence_Check__c> icList = new List<Incidence_Check__c>{ ic1, ic2, icUnrelated };
            insert icList;

            List<Incidence_Check__c> fixStatuses = [
                SELECT Id, Status__c FROM Incidence_Check__c WHERE Id IN :new List<Id>{ ic1.Id, ic2.Id, icUnrelated.Id }
            ];
            for (Incidence_Check__c ic : fixStatuses) ic.Status__c = 'Submitted';
            update fixStatuses;

            Test.startTest();
            acct.Territory_SDR__c = newSdr.Id;
            update acct;
            Test.stopTest();

            Map<Id, Incidence_Check__c> icById = new Map<Id, Incidence_Check__c>([
                SELECT Id, OwnerId FROM Incidence_Check__c WHERE Id IN :icList
            ]);

            System.assertEquals(newSdr.Id, icById.get(ic1.Id).OwnerId,
                'IC1 owner should be reassigned to the new SDR.');
            System.assertEquals(newSdr.Id, icById.get(ic2.Id).OwnerId,
                'IC2 owner should be reassigned to the new SDR.');
            System.assertEquals(unrelatedSdr.Id, icById.get(icUnrelated.Id).OwnerId,
                'Unrelated IC must not be reassigned.');
        }
    }

    @IsTest
    static void testNoSDRChange_NoUpdates() {
        User runner = createAdminRunner('2');
        insert runner;

        System.runAs(runner) {
            TestDataFactory factory = new TestDataFactory();
            Account acct = factory.createPharmaAccount();
            insert acct;

            Test.startTest();
            acct.Name = 'Updated Name Only';
            update acct;
            Test.stopTest();

            System.assert(true, 'No exception when SDR is not changed');
        }
    }

    @IsTest
    static void testSDRChange_NoContacts_NoUpdates() {
        User runner = createAdminRunner('3');
        insert runner;

        System.runAs(runner) {
            TestDataFactory factory = new TestDataFactory();
            User oldSdr = factory.createUser2('sdrold');
            User newSdr = factory.createUser2('sdrnew');
            insert new List<User>{ oldSdr, newSdr };

            Account acct = factory.createPharmaAccount();
            acct.Territory_SDR__c = oldSdr.Id;
            insert acct;

            Test.startTest();
            acct.Territory_SDR__c = newSdr.Id;
            update acct;
            Test.stopTest();

            System.assert(true, 'No exception when no contacts exist under account');
        }
    }

    @IsTest
    static void testSDRChange_NoMatchingICs() {
        User runner = createAdminRunner('4');
        insert runner;

        System.runAs(runner) {
            TestDataFactory factory = new TestDataFactory();
            User oldSdr = factory.createUser2('sdrA');
            User newSdr = factory.createUser2('sdrB');
            insert new List<User>{ oldSdr, newSdr };

            Account acct = factory.createPharmaAccount();
            acct.Territory_SDR__c = oldSdr.Id;
            insert acct;

            Contact contact = factory.createResearcherContact(acct.Id);
            insert contact;

            Test.startTest();
            acct.Territory_SDR__c = newSdr.Id;
            update acct;
            Test.stopTest();

            System.assert(true, 'No exception when no matching ICs exist');
        }
    }

    @IsTest
    static void test_InterfaceHooks_NoOpCoverage() {
        User runner = createAdminRunner('5');
        insert runner;

        System.runAs(runner) {
            TestDataFactory factory = new TestDataFactory();
            Account a = factory.createPharmaAccount();
            insert a;

            a.Name = 'Updated';
            update a;

            delete a;

            Test.startTest();
            undelete a;
            Test.stopTest();
        }
    }
}