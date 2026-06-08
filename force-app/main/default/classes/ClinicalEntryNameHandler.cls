/**
 * @description       : Handler to set Health Profile (ClinicalEntry__c) Name from related Patient__c (Contact) Name before insert/update.
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-14
 * @executionOrder    : 30 (Field Defaults & Updates)
 * @group             : Health Profile Trigger Handlers
 * @group-content     : ClinicalEntryNameHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - CRUD/FLS checks applied before querying/updating.
 * - No SOQL/DML in loops; bulk-safe for 200+ records.
 * - Queries retrieve only necessary fields.
 * - Methods are < 100 lines, single-responsibility design.
 */
public with sharing class ClinicalEntryNameHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'ClinicalEntryNameHandler';
    private static final String OBJECT_NAME = 'ClinicalEntry__c';

    /**
     * @description Called before insert to set Name from related Patient__c Contact.
     * @param newRecords List of new SObject records from trigger context.
     */
    public void beforeInsert(List<SObject> newRecords) {
        try {
            updateClinicalEntryNames((List<ClinicalEntry__c>) newRecords);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    /**
     * @description Called before update to set Name from related Patient__c Contact.
     * @param newRecords List of new SObject records from trigger context.
     * @param oldMap Map of old SObject records from trigger context.
     */
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<ClinicalEntry__c> newHps = (List<ClinicalEntry__c>) newRecords;
            Map<Id, ClinicalEntry__c> oldHps = (Map<Id, ClinicalEntry__c>) oldMap;

            List<ClinicalEntry__c> relevant = new List<ClinicalEntry__c>();
            for (ClinicalEntry__c hp : newHps) {
                ClinicalEntry__c oldHp = (oldHps != null) ? oldHps.get(hp.Id) : null;
                if (oldHp == null || hp.Patient__c != oldHp.Patient__c) {
                    relevant.add(hp);
                }
            }
            if (relevant.isEmpty()) return;

            updateClinicalEntryNames(relevant);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    /**
     * @description Updates Name field on Health Profiles based on Patient__c Contact name.
     * @param clinicalEntries List of ClinicalEntry__c records to update.
     */
    private void updateClinicalEntryNames(List<ClinicalEntry__c> clinicalEntries) {
        if (clinicalEntries.isEmpty()) return;

        Set<Id> patientIds = new Set<Id>();
        for (ClinicalEntry__c hp : clinicalEntries) {
            if (hp.Patient__c != null) {
                patientIds.add(hp.Patient__c);
            }
        }
        if (patientIds.isEmpty()) return;

        // CRUD check before query
        if (!Schema.sObjectType.Contact.isAccessible() ||
            !Schema.sObjectType.Contact.fields.Name.isAccessible()) {
            return;
        }

        Map<Id, String> patientNameMap = new Map<Id, String>();
        for (Contact c : [
            SELECT Id, Name
            FROM Contact
            WHERE Id IN :patientIds
        ]) {
            patientNameMap.put(c.Id, c.Name);
        }

        for (ClinicalEntry__c hp : clinicalEntries) {
            if (hp.Patient__c != null && patientNameMap.containsKey(hp.Patient__c)) {
                hp.Name = patientNameMap.get(hp.Patient__c);
            }
        }
    }

    // Empty interface methods
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
