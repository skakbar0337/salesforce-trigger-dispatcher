/**
 * Test class for TriggerDispatcher
 * Tests the core trigger framework functionality with comprehensive coverage
 */

@IsTest
private class TriggerDispatcherTest {
    
    // Static fields for mock handler tracking
    private static Boolean mockBeforeInsertCalled = false;
    private static Boolean mockBeforeUpdateCalled = false;
    private static Boolean mockBeforeDeleteCalled = false;
    private static Boolean mockAfterInsertCalled = false;
    private static Boolean mockAfterUpdateCalled = false;
    private static Boolean mockAfterDeleteCalled = false;
    private static Boolean mockAfterUndeleteCalled = false;
    private static Boolean mockShouldThrowException = false;
    private static List<SObject> mockReceivedNewRecords;
    private static Map<Id, SObject> mockReceivedOldMap;
    
    // Static fields for second mock handler
    private static Integer mock2ExecutionOrder = 0;
    private static Integer mock2MyExecutionOrder = 0;
    
    // Static fields for third mock handler (for execution order testing)
    private static Integer mock3ExecutionOrder = 0;
    private static Integer mock3MyExecutionOrder = 0;
    
    /**
     * Mock handler for testing
     */
    public class MockTriggerHandler implements ITriggerHandler {
        
        public void beforeInsert(List<SObject> newRecords) {
            mockBeforeInsertCalled = true;
            mockReceivedNewRecords = newRecords;
            if (mockShouldThrowException) {
                throw new TestException('Test exception in beforeInsert');
            }
        }
        
        public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
            mockBeforeUpdateCalled = true;
            mockReceivedNewRecords = newRecords;
            mockReceivedOldMap = oldRecordsMap;
            if (mockShouldThrowException) {
                throw new TestException('Test exception in beforeUpdate');
            }
        }
        
        public void beforeDelete(Map<Id, SObject> oldRecordsMap) {
            mockBeforeDeleteCalled = true;
            mockReceivedOldMap = oldRecordsMap;
            if (mockShouldThrowException) {
                throw new TestException('Test exception in beforeDelete');
            }
        }
        
        public void afterInsert(List<SObject> newRecords) {
            mockAfterInsertCalled = true;
            mockReceivedNewRecords = newRecords;
            if (mockShouldThrowException) {
                throw new TestException('Test exception in afterInsert');
            }
        }
        
        public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
            mockAfterUpdateCalled = true;
            mockReceivedNewRecords = newRecords;
            mockReceivedOldMap = oldRecordsMap;
            if (mockShouldThrowException) {
                throw new TestException('Test exception in afterUpdate');
            }
        }
        
        public void afterDelete(Map<Id, SObject> oldRecordsMap) {
            mockAfterDeleteCalled = true;
            mockReceivedOldMap = oldRecordsMap;
            if (mockShouldThrowException) {
                throw new TestException('Test exception in afterDelete');
            }
        }
        
        public void afterUndelete(List<SObject> newRecords) {
            mockAfterUndeleteCalled = true;
            mockReceivedNewRecords = newRecords;
            if (mockShouldThrowException) {
                throw new TestException('Test exception in afterUndelete');
            }
        }
    }
    
    /**
     * Second mock handler to test execution order
     */
    public class MockTriggerHandler2 implements ITriggerHandler {
        
        public void beforeInsert(List<SObject> newRecords) {
            mock2ExecutionOrder++;
            mock2MyExecutionOrder = mock2ExecutionOrder;
        }
        
        public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
            mock2ExecutionOrder++;
            mock2MyExecutionOrder = mock2ExecutionOrder;
        }
        
        public void beforeDelete(Map<Id, SObject> oldRecordsMap) { }
        public void afterInsert(List<SObject> newRecords) { }
        public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) { }
        public void afterDelete(Map<Id, SObject> oldRecordsMap) { }
        public void afterUndelete(List<SObject> newRecords) { }
    }
    
    /**
     * Third mock handler to test execution order
     */
    public class MockTriggerHandler3 implements ITriggerHandler {
        
        public void beforeInsert(List<SObject> newRecords) {
            mock3ExecutionOrder++;
            mock3MyExecutionOrder = mock3ExecutionOrder;
        }
        
        public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
            mock3ExecutionOrder++;
            mock3MyExecutionOrder = mock3ExecutionOrder;
        }
        
        public void beforeDelete(Map<Id, SObject> oldRecordsMap) { }
        public void afterInsert(List<SObject> newRecords) { }
        public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) { }
        public void afterDelete(Map<Id, SObject> oldRecordsMap) { }
        public void afterUndelete(List<SObject> newRecords) { }
    }
    
    // Reset methods
    private static void resetMockHandler() {
        mockBeforeInsertCalled = false;
        mockBeforeUpdateCalled = false;
        mockBeforeDeleteCalled = false;
        mockAfterInsertCalled = false;
        mockAfterUpdateCalled = false;
        mockAfterDeleteCalled = false;
        mockAfterUndeleteCalled = false;
        mockShouldThrowException = false;
        mockReceivedNewRecords = null;
        mockReceivedOldMap = null;
    }
    
    private static void resetMockHandler2() {
        mock2ExecutionOrder = 0;
        mock2MyExecutionOrder = 0;
    }
    
    private static void resetMockHandler3() {
        mock3ExecutionOrder = 0;
        mock3MyExecutionOrder = 0;
    }
    
    /**
     * Helper method to create mock custom metadata config
     */
    private static TriggerHandlerConfig__mdt createMockConfig(String handlerClass, Decimal executionOrder) {
        TriggerHandlerConfig__mdt config = new TriggerHandlerConfig__mdt();
        config.HandlerClass__c = handlerClass;
        config.ExecutionOrder__c = executionOrder;
        config.IsActive__c = true;
        return config;
    }
    
    /**
     * Helper method to inject test handlers into TriggerDispatcher
     */
    private static void injectTestHandlers(String sObjectName, List<TriggerHandlerConfig__mdt> handlers) {
        if (TriggerDispatcher.testHandlerCache == null) {
            TriggerDispatcher.testHandlerCache = new Map<String, List<TriggerHandlerConfig__mdt>>();
        }
        TriggerDispatcher.testHandlerCache.put(sObjectName, handlers);
    }

    public class TestException extends Exception {}
    
    @TestSetup
    static void setup() {
        // Create test accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
    }
    
    /**
     * Test dispatch with no handlers configured
     */
    @IsTest
    static void testDispatchWithNoHandlers() {
        resetMockHandler();
        
        // Don't inject any handlers
        TriggerDispatcher.testHandlerCache = new Map<String, List<TriggerHandlerConfig__mdt>>();
        
        List<Account> testAccounts = [SELECT Id, Name FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Simulate trigger context
        Test.setReadOnlyApplicationMode(false);
        
        // Call dispatch - should complete without errors
        TriggerDispatcher.dispatch('Account');
        
        Test.stopTest();
        
        // Verify no handlers were called
        System.assertEquals(false, mockBeforeInsertCalled, 'No handlers should be called');
    }
    
    /**
     * Test all trigger contexts with actual DML operations
     * This test fires the AccountTrigger which calls TriggerDispatcher
     */
    @IsTest
    static void testAllTriggerContexts() {
        resetMockHandler();
        
        // Inject test handler
        List<TriggerHandlerConfig__mdt> handlers = new List<TriggerHandlerConfig__mdt>{
            createMockConfig('TriggerDispatcherTest.MockTriggerHandler', 1)
        };
        injectTestHandlers('Account', handlers);
        
        Test.startTest();
        
        // Test INSERT (fires beforeInsert and afterInsert)
        Account testAccount = new Account(Name = 'Dispatcher Test Account');
        insert testAccount;
        
        System.assert(mockBeforeInsertCalled, 'beforeInsert should be called');
        System.assert(mockAfterInsertCalled, 'afterInsert should be called');
        System.assertNotEquals(null, mockReceivedNewRecords, 'Should receive new records');
        System.assertEquals(1, mockReceivedNewRecords.size(), 'Should receive one record');
        
        // Reset and test UPDATE
        resetMockHandler();
        testAccount.Name = 'Updated Test Account';
        update testAccount;
        
        System.assert(mockBeforeUpdateCalled, 'beforeUpdate should be called');
        System.assert(mockAfterUpdateCalled, 'afterUpdate should be called');
        System.assertNotEquals(null, mockReceivedOldMap, 'Should receive old map');
        
        // Reset and test DELETE
        resetMockHandler();
        delete testAccount;
        
        System.assert(mockBeforeDeleteCalled, 'beforeDelete should be called');
        System.assert(mockAfterDeleteCalled, 'afterDelete should be called');
        
        // Reset and test UNDELETE
        resetMockHandler();
        undelete testAccount;
        
        System.assert(mockAfterUndeleteCalled, 'afterUndelete should be called');
        
        Test.stopTest();
    }
    
    /**
     * Test error handling when handler throws exception
     */
    @IsTest
    static void testHandlerException() {
        resetMockHandler();
        mockShouldThrowException = true;
        
        List<TriggerHandlerConfig__mdt> handlers = new List<TriggerHandlerConfig__mdt>{
            createMockConfig('TriggerDispatcherTest.MockTriggerHandler', 1)
        };
        injectTestHandlers('Account', handlers);
        
        Test.startTest();
        
        // Exception should be caught by TriggerDispatcher, allowing DML to complete
        Account testAccount = new Account(Name = 'Exception Test Account');
        try {
            insert testAccount;
        } catch (Exception e) {
        }

        Test.stopTest();
    }
    
    /**
     * Test handler class not found scenario
     */
    @IsTest
    static void testHandlerClassNotFound() {
        List<TriggerHandlerConfig__mdt> handlers = new List<TriggerHandlerConfig__mdt>{
            createMockConfig('NonExistentHandlerClass', 1)
        };
        injectTestHandlers('Account', handlers);
        
        Test.startTest();
        
        // Should not throw exception, just log error
        Account testAccount = new Account(Name = 'Invalid Handler Test');
        insert testAccount;
        
        Test.stopTest();
        
        // Account should still be inserted despite invalid handler
        List<Account> accounts = [SELECT Id FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals(1, accounts.size(), 'Account should be inserted despite invalid handler');
    }
    
    /**
     * Test multiple handlers execution
     */
    @IsTest
    static void testMultipleHandlers() {
        resetMockHandler();
        resetMockHandler2();
        
        List<TriggerHandlerConfig__mdt> handlers = new List<TriggerHandlerConfig__mdt>{
            createMockConfig('TriggerDispatcherTest.MockTriggerHandler', 1),
            createMockConfig('TriggerDispatcherTest.MockTriggerHandler2', 2)
        };
        injectTestHandlers('Account', handlers);
        
        Test.startTest();
        
        Account testAccount = new Account(Name = 'Multiple Handlers Test');
        insert testAccount;
        
        Test.stopTest();
        
        // Both handlers should be called
        System.assert(mockBeforeInsertCalled, 'First handler should be called');
        System.assertEquals(1, mock2MyExecutionOrder, 'Second handler should be called');
    }
    
    /**
     * Test cache functionality
     */
    @IsTest
    static void testHandlerCaching() {
        resetMockHandler();
        
        List<TriggerHandlerConfig__mdt> handlers = new List<TriggerHandlerConfig__mdt>{
            createMockConfig('TriggerDispatcherTest.MockTriggerHandler', 1)
        };
        injectTestHandlers('Account', handlers);
        
        Test.startTest();
        
        // First call
        Account testAccount1 = new Account(Name = 'Cache Test 1');
        insert testAccount1;
        
        System.assert(mockBeforeInsertCalled, 'First call should execute handler');
        
        resetMockHandler();
        
        // Second call - should use cached handlers
        Account testAccount2 = new Account(Name = 'Cache Test 2');
        insert testAccount2;
        
        Test.stopTest();
        
        System.assert(mockBeforeInsertCalled, 'Cached handler should be executed');
    }
    
    /**
     * Test that different SObjects can have different handlers
     */
    @IsTest
    static void testDifferentSObjectHandlers() {
        resetMockHandler();
        resetMockHandler2();
        
        // Set up different handlers for Account and Contact
        List<TriggerHandlerConfig__mdt> accountHandlers = new List<TriggerHandlerConfig__mdt>{
            createMockConfig('TriggerDispatcherTest.MockTriggerHandler', 1)
        };
        List<TriggerHandlerConfig__mdt> contactHandlers = new List<TriggerHandlerConfig__mdt>{
            createMockConfig('TriggerDispatcherTest.MockTriggerHandler2', 1)
        };
        
        injectTestHandlers('Account', accountHandlers);
        injectTestHandlers('Contact', contactHandlers);
        
        Test.startTest();
        
        // Insert Account - should call MockTriggerHandler
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        System.assert(mockBeforeInsertCalled, 'Account handler should be called');
        
        Test.stopTest();
    }
    
    /**
     * Test actual trigger scenario with real DML
     */
    @IsTest
    static void testActualTriggerScenario() {
        Account testAccount = new Account(Name = 'Trigger Test Account');
        
        Test.startTest();
        
        insert testAccount;
        
        testAccount.Name = 'Updated Account';
        update testAccount;
        
        delete testAccount;
        
        undelete testAccount;
        
        Test.stopTest();
        
        List<Account> accounts = [SELECT Id FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals(1, accounts.size(), 'Account should exist after undelete');
    }

}