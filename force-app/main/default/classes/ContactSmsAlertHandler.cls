/**
 * @description
 * Invokes SMS notification logic using FiveNineSMSService when a Contact is updated.
 * Intended for post-update communication automation.
 * Author: S.M Akbar
 * @executionOrder 50 (Complex Logic Handler)
 */
public with sharing class ContactSmsAlertHandler implements ITriggerHandler {

    /**
     * @param newList List of updated Contact records
     * @param oldMap Previous state of Contact records
     */
    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        try {
            FiveNineSMSService.checkForSMSSendToContact(oldMap, Trigger.newMap);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, e.getMessage());
            // Re-throw to ensure trigger failure is visible
            throw e;
        }
    }

    //Empty Stubs
    public void beforeInsert(List<SObject> newList) {
    }
    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
    }
    public void beforeDelete(Map<Id, SObject> oldMap) {
    }
    public void afterInsert(List<SObject> newList) {
    }
    public void afterDelete(Map<Id, SObject> oldMap) {
    }
    public void afterUndelete(List<SObject> newList) {
    }
}
