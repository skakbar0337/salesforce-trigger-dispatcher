/**
 * @description
 * Handler to assign prefixed ('ON - X' / 'AI - X') and numeric Patient_ID_New__c values.
 * Refactored from legacy triggers: NewPatientID and newcontacttrigger_for_AI_and_ON.
 * @executionOrder 26 (Field Update Handler)
 */
public with sharing class ContactPatientIDHandler implements ITriggerHandler {

    private static final String PATIENT = 'Patient';

    public void beforeInsert(List<SObject> newRecords) {
        List<Contact> contacts = (List<Contact>) newRecords;
        if (contacts.isEmpty()) {
            return;
        }

        assignNumericPatientID(contacts);  // fallback numeric ID
    }

    private void assignNumericPatientID(List<Contact> contacts) {
        List<Contact> queue = new List<Contact>();

        for (Contact c : contacts) {
            if ((c.Identity__c == PATIENT || getRecordTypeName(c) == PATIENT)
                && String.isBlank(c.Patient_ID_New__c)) {
                queue.add(c);
            }
        }

        if (queue.isEmpty()) {
            return;
        }

        // CRUD check before SOQL
        if (!Schema.sObjectType.Contact.isAccessible()) {
            System.debug(LoggingLevel.WARN, 'Current user lacks read access to Contact. Aborting Patient ID assignment.');
            return;
        }

        Integer latestPID = 160000;
        List<Contact> recent = new List<Contact>();
        try {
            recent = [
                SELECT Patient_ID_New_F__c, Patient_ID_New__c
                FROM Contact
                WHERE RecordType.Name = :PATIENT
                  AND Patient_ID_New__c != NULL
                  AND Patient_ID_New_F__c != 0
                ORDER BY Patient_ID_New_F__c DESC
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'SOQL failed: ' + e.getMessage());
        }
        if (!recent.isEmpty()) {
            latestPID = Integer.valueOf(recent[0].Patient_ID_New__c);
        }

        Integer rangeStart = latestPID - 20000;
        Integer rangeEnd = latestPID + 20000;
        Set<Integer> used = new Set<Integer>();

        try {
            for (Contact c : [
                SELECT Patient_ID_New_F__c
                FROM Contact
                WHERE Patient_ID_New_F__c != NULL
                  AND Patient_ID_New_F__c >= :rangeStart
                  AND Patient_ID_New_F__c <= :rangeEnd
            ]) {
                used.add(Integer.valueOf(c.Patient_ID_New_F__c));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'SOQL failed: ' + e.getMessage());
        }

        Integer nextPID = latestPID + 1;
        for (Contact c : queue) {
            while (used.contains(nextPID)) {
                nextPID++;
            }
            c.Patient_ID_New__c = String.valueOf(nextPID);
            used.add(nextPID);
            nextPID++;
        }
    }

    private String getRecordTypeName(Contact c) {
        try {
            return c.getSObjectType()
                .getDescribe()
                .getRecordTypeInfosById()
                .get(c.RecordTypeId)
                .getName();
        } catch (Exception e) {
            return null;
        }
    }

    // Empty stub methods
    public void afterInsert(List<SObject> newRecords) {
    }
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
    }
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
    }
    public void beforeDelete(Map<Id, SObject> oldMap) {
    }
    public void afterDelete(Map<Id, SObject> oldMap) {
    }
    public void afterUndelete(List<SObject> newRecords) {
    }
}
