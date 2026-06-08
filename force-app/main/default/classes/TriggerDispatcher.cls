/**
 * Main trigger dispatcher that orchestrates trigger execution
 * Reads custom metadata to determine which handlers to execute
 */

public class TriggerDispatcher {

    private static double VERSION = 1.1;
    
    // Cache for handler configurations to improve performance
    private static Map<String, List<TriggerHandlerConfig__mdt>> handlerCache = new Map<String, List<TriggerHandlerConfig__mdt>>();
    
    // Test injection point for handler configurations
    @TestVisible
    private static Map<String, List<TriggerHandlerConfig__mdt>> testHandlerCache = null;
    
    // Static initializer to pre-load all handlers into cache
    static {
        loadAllHandlers();
    }
    
    /**
     * Main dispatch method - call this from triggers
     * @param sObjectName The name of the SObject being triggered
     */
    public static void dispatch(String sObjectName) {
        start();

        // Skip execution if triggers are disabled (useful for data loads)
        if (isTriggerDisabled(sObjectName)) {
            System.debug(LoggingLevel.WARN, 'Triggers are disabled for ' + sObjectName);
            finish();
        }
        
        // Get handlers for this object
        List<TriggerHandlerConfig__mdt> handlers = getHandlers(sObjectName);

        if (handlers == null || handlers.isEmpty()) {
            // No handlers configured
            System.debug(LoggingLevel.WARN, 'No trigger handlers configured for ' + sObjectName);
            finish();
            return;
        }   
        
        // Execute each handler
        for (TriggerHandlerConfig__mdt config : handlers) {
            try {
                executeHandler(config);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Error executing handler ' + config.HandlerClass__c + ': ' + ex.getMessage());
                throw new TriggerDispatcherException('Error executing handler ' + config.HandlerClass__c + ': ' + ex.getMessage());
            }
        }

        finish();
    }

    private static string getObjectType() {
        return (Trigger.isExecuting && Trigger.new != null && !Trigger.new.isEmpty()) 
               ? Trigger.new[0].getSObjectType().getDescribe().getName() 
               : '';
    }

    private static void start() {
        System.debug(LoggingLevel.DEBUG, 'TriggerDispatcher.start() — before context');
    }

    private static void finish() {
        System.debug(LoggingLevel.DEBUG, 'TriggerDispatcher.finish() — after context');
    }
    
    /**
     * Load all active handlers into the cache
     * Called automatically via static initializer in production
     * Called on-demand in test context without injection
     */
    @TestVisible
    private static void loadAllHandlers() 
    {
        try {

            List<TriggerHandlerConfig__mdt> allHandlers = [
                SELECT Id, HandlerClass__c, ExecutionOrder__c, IsActive__c, SObjectName__c
                FROM   TriggerHandlerConfig__mdt
                WHERE  IsActive__c = true
                ORDER BY SObjectName__c, ExecutionOrder__c ASC, HandlerClass__c ASC
            ];
            
            // Group handlers by SObject
            for (TriggerHandlerConfig__mdt handler : allHandlers) {
                if (!handlerCache.containsKey(handler.SObjectName__c)) {
                    handlerCache.put(handler.SObjectName__c, new List<TriggerHandlerConfig__mdt>());
                }
                handlerCache.get(handler.SObjectName__c).add(handler);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error loading trigger handlers from metadata: ' + ex.getMessage());
        }
    }
    
    /**
     * Get handlers for the specified SObject from cache or custom metadata
     */
    private static List<TriggerHandlerConfig__mdt> getHandlers(String sObjectName) {
        // In test context with injected handlers, use those exclusively
        if (Test.isRunningTest() && testHandlerCache != null) {
            return testHandlerCache.containsKey(sObjectName) ? 
                   testHandlerCache.get(sObjectName) : 
                   new List<TriggerHandlerConfig__mdt>();
        }
        
        // For test context without injection, load metadata if cache is empty
        if (Test.isRunningTest() && handlerCache.isEmpty()) {
            loadAllHandlers();
        }
        
        // Return from cache (or empty list if no handlers configured for this SObject)
        return handlerCache.containsKey(sObjectName) ? 
               handlerCache.get(sObjectName) : 
               new List<TriggerHandlerConfig__mdt>();
    }
    
    /**
     * Clear the handler cache - useful for testing
     */
    @TestVisible
    private static void clearCache() {
        handlerCache.clear();
        testHandlerCache = null;
    }
    
    /**
     * Execute a single handler with error handling
     */
    private static void executeHandler(TriggerHandlerConfig__mdt config) {
        // Dynamically instantiate the handler class
        Type handlerType = Type.forName(config.HandlerClass__c);
        if (handlerType == null) {
            logError('Handler class not found: ' + config.HandlerClass__c);
            return;
        }
        
        ITriggerHandler handler = (ITriggerHandler) handlerType.newInstance();
        
        // Route to appropriate method based on trigger context
        if (Trigger.isBefore) {
            if (Trigger.isInsert) {
                handler.beforeInsert(Trigger.new);
            } else if (Trigger.isUpdate) {
                handler.beforeUpdate(Trigger.new, Trigger.oldMap);
            } else if (Trigger.isDelete) {
                handler.beforeDelete(Trigger.oldMap);
            }
        } else if (Trigger.isAfter) {
            if (Trigger.isInsert) {
                handler.afterInsert(Trigger.new);
            } else if (Trigger.isUpdate) {
                handler.afterUpdate(Trigger.new, Trigger.oldMap);
            } else if (Trigger.isDelete) {
                handler.afterDelete(Trigger.oldMap);
            } else if (Trigger.isUndelete) {
                handler.afterUndelete(Trigger.new);
            }
        }
    }
    
    /**
     * Check if triggers are disabled for this object
     * Can be controlled via custom settings or custom metadata
     */
    private static Boolean isTriggerDisabled(String sObjectName) {
        // TODO
        // For example, check a custom setting or custom metadata
        // For now, returning false to keep triggers enabled
        return false;
    }
    
    private static void logError(String errorMessage) {
        System.debug(LoggingLevel.ERROR, errorMessage);
    }
    
    // Custom exception class
    public class TriggerDispatcherException extends Exception {}
}