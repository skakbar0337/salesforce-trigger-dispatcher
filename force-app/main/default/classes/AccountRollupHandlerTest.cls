@IsTest(seeAllData=false)
private class AccountRollupHandlerTest {

    private static void setupMockRules() {
        AccountRollupHandler.mockRules = new List<Account_Rollup_Rule__mdt>{
            new Account_Rollup_Rule__mdt(
                DeveloperName = 'AnnualRevenueMax',
                Label = 'AnnualRevenueMax',
                Source_Field_API_Name__c = 'AnnualRevenue',
                Source_Field_Datatype__c = 'NUMBER/DECIMAL/CURRENCY',
                Rollup_Type__c = 'MAX',
                Destination_API_Field_Name__c = 'AnnualRevenue',
                Active__c = true
            )
        };
    }

    @IsTest
    static void test_afterInsert_rollupMaxRevenue() {
        setupMockRules();
        TestDataFactory f = new TestDataFactory();
        Account shell = f.createShellAccount(); insert shell;
        Account child1 = f.createPharmaAccount(); child1.ParentId = shell.Id; child1.AnnualRevenue = 145200;
        Account child2 = f.createPharmaAccount(); child2.ParentId = shell.Id; child2.AnnualRevenue = 200000;
        insert new List<Account>{child1, child2};

        AccountRollupHandler handler = new AccountRollupHandler();
        Test.startTest();
        handler.afterInsert(new List<SObject>{child1, child2});
        Test.stopTest();

        Account shellAfter = [SELECT AnnualRevenue FROM Account WHERE Id=:shell.Id];
        System.assertEquals(200000, shellAfter.AnnualRevenue);
    }

    @IsTest
    static void test_afterDelete_nullifiesShellFieldsWhenEmpty() {
        setupMockRules();
        TestDataFactory f = new TestDataFactory();
        Account shell = f.createShellAccount(); insert shell;
        shell.AnnualRevenue = 120000; update shell;

        Account child = f.createPharmaAccount(); child.ParentId = shell.Id; child.AnnualRevenue = 50000; insert child;
        delete child;

        AccountRollupHandler handler = new AccountRollupHandler();
        Test.startTest();
        handler.afterDelete(new Map<Id, SObject>{child.Id => child});
        Test.stopTest();

        Account shellAfter = [SELECT AnnualRevenue FROM Account WHERE Id=:shell.Id];
        System.assertEquals(null, shellAfter.AnnualRevenue);
    }

    @IsTest
    static void test_emptyInputs_safe() {
        setupMockRules();
        AccountRollupHandler handler = new AccountRollupHandler();
        Test.startTest();
        handler.afterInsert(new List<SObject>());
        handler.afterUpdate(new List<SObject>(), new Map<Id, SObject>());
        handler.afterDelete(new Map<Id, SObject>());
        Test.stopTest();
        System.assert(true, 'Empty inputs handled safely');
    }

    @IsTest
    static void test_defaultConstructor_smoke() {
        Test.startTest();
        AccountRollupHandler handler = new AccountRollupHandler();
        Test.stopTest();
        System.assertNotEquals(null, handler, 'Default constructor instantiated successfully');
    }
}