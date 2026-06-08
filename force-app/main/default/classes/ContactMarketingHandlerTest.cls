@isTest
public class ContactMarketingHandlerTest {

    @isTest
static void testAddResearcherToRevenueOpsCampaign() {
    // Arrange
    TestDataFactory factory = new TestDataFactory();

    // Campaign must exist and be active
    Campaign campaign = new Campaign(Name = 'Revenue Operations Funnel Campaign', IsActive = true);
    insert campaign;

    // Resolve Researcher (dev name)
    Id scientistRTId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                        .get('Researcher').getRecordTypeId();

    Account account = factory.createPharmaAccount();
    insert account;

    Contact c = new Contact(
        FirstName = 'Jane',
        LastName  = 'Doe',
        Email     = 'jane.doe@example.com',
        RecordTypeId = scientistRTId,
        AccountId = account.Id
    );

    Test.startTest();
    insert c;

    // guarantee the handler logic runs in test:
    ITriggerHandler h = new ContactMarketingHandler();
    h.afterInsert(new List<SObject>{ c });

    Test.stopTest();

    // Assert
    List<CampaignMember> members = [
        SELECT Id, ContactId, CampaignId, Status
        FROM CampaignMember
        WHERE ContactId = :c.Id
    ];
    System.assertEquals(1, members.size(), 'Contact should be added to campaign');
    System.assertEquals('Responded', members[0].Status);
}

    @isTest
    static void testNoCampaignExists() {
        // This test ensures that if the campaign doesn't exist, no exception is thrown

        Id scientistRTId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                            .get('Researcher')
                            .getRecordTypeId();

        Account a = new Account(Name = 'No Campaign Co');
        insert a;

        Contact c = new Contact(
            FirstName = 'Ghost',
            LastName = 'Researcher',
            Email = 'ghost@example.com',
            RecordTypeId = scientistRTId,
            AccountId = a.Id
        );
        //c.put('RecordTypeName__c', 'Scientist');

        Test.startTest();
        insert c;
        Test.stopTest();

        List<CampaignMember> members = [
            SELECT Id FROM CampaignMember WHERE ContactId = :c.Id
        ];
        System.assertEquals(0, members.size(), 'Should not create campaign member if campaign does not exist');
    }

    @isTest
    static void coverStubMethods() {
        ITriggerHandler handler = new ContactMarketingHandler();
        handler.beforeInsert(new List<SObject>());
        handler.beforeUpdate(new List<SObject>(), new Map<Id, SObject>());
        handler.afterUpdate(new List<SObject>(), new Map<Id, SObject>());
        handler.beforeDelete(new Map<Id, SObject>());
        handler.afterDelete(new Map<Id, SObject>());
        handler.afterUndelete(new List<SObject>());
    }
}