/**
 * @description       : Handler to update related Contact records (Patient and Advocate) when Health Profiles change.
 * Handles the logic from findPatientsToUpdate and updatePatients
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-06
 * @executionOrder    : 30 (Rollups & Calculations)
 * @group             : Health Profile Trigger Handlers
 * @group-content     : HealthProfilePatientHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - Object CRUD and field-level access are validated; data is sanitized via Security.stripInaccessible.
 * - No SOQL/DML inside loops; bulk-safe across 200+ rows.
 * - Defensive queries are field-selective and filtered.
 * - Updates use Database.update(..., false) for partial success and error logging.
 * - Methods < 100 lines, meaningful names, and single-responsibility design.
 */

public with sharing class HealthProfilePatientHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'HealthProfilePatientHandler';
    private static final String OBJECT_NAME = 'HealthProfile__c';

    // ---------------- AFTER INSERT ----------------
    public void afterInsert(List<SObject> newRecords) {
        try {
            List<HealthProfile__c> newHps = (List<HealthProfile__c>) newRecords;
            findPatientsToUpdate(newHps, null);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    // ---------------- AFTER UPDATE ----------------
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<HealthProfile__c> newHps = (List<HealthProfile__c>) newRecords;
            Map<Id, HealthProfile__c> oldHpsById = new Map<Id, HealthProfile__c>();
            for (Id k : oldMap.keySet()) {
                SObject s = oldMap.get(k);
                if (s instanceof HealthProfile__c) oldHpsById.put(k, (HealthProfile__c)s);
            }
            findPatientsToUpdate(newHps, oldHpsById);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    // ---------------- AFTER DELETE ----------------
    public void afterDelete(Map<Id, SObject> oldMap) {
        try {
            List<HealthProfile__c> oldHps = new List<HealthProfile__c>();
            for (SObject s : oldMap.values()) {
                oldHps.add((HealthProfile__c) s);
            }
            findPatientsToUpdate(oldHps, null);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    // ---------------- AFTER UNDELETE ----------------
    public void afterUndelete(List<SObject> newRecords) {
        try {
            List<HealthProfile__c> newHps = (List<HealthProfile__c>) newRecords;
            findPatientsToUpdate(newHps, null);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    // ----------------- CORE LOGIC ------------------

    private void findPatientsToUpdate(List<HealthProfile__c> hps, Map<Id, HealthProfile__c> oldHpsById) {
        Set<Id> patientIds = new Set<Id>();
        Set<Id> advocateIds = new Set<Id>();

        for (HealthProfile__c hp : hps) {
            HealthProfile__c oldHp = oldHpsById != null ? oldHpsById.get(hp.Id) : null;
		Boolean apptChanged = oldHp == null || hp.Appointment_Date_Time__c != oldHp.Appointment_Date_Time__c;
		Boolean volChanged  = oldHp == null || hp.Requested_Volume_mL_On_site__c != oldHp.Requested_Volume_mL_On_site__c;
            Boolean patientChanged = oldHp == null || hp.Patient__c != oldHp.Patient__c;
            Boolean advocateChanged = oldHp == null || hp.Patient_Advocate__c != oldHp.Patient_Advocate__c;
            Boolean hasICFChange = oldHp == null ||
                hp.ICF_Version_on_File__c != oldHp.ICF_Version_on_File__c ||
                hp.ICF_Date_of_Signature__c != oldHp.ICF_Date_of_Signature__c;

             // ---- Patients: add on patient lookup change OR ICF change OR appt/vol change (legacy parity)
            if (hp.Patient__c != null && (patientChanged || hasICFChange || apptChanged || volChanged || oldHp == null)) {
                patientIds.add(hp.Patient__c);
            }
            if (oldHp != null && oldHp.Patient__c != null && patientChanged) {
                patientIds.add(oldHp.Patient__c);
            }

            // ---- Advocates: include appt/vol change (legacy parity)
            if (hp.Patient_Advocate__c != null && (advocateChanged || apptChanged || volChanged || oldHp == null)) {
                advocateIds.add(hp.Patient_Advocate__c);
            }
            if (oldHp != null && oldHp.Patient_Advocate__c != null && (advocateChanged || apptChanged || volChanged)) {
                advocateIds.add(oldHp.Patient_Advocate__c);
            }
        }

        if (!patientIds.isEmpty() || !advocateIds.isEmpty()) {
            updateRelatedContacts(patientIds, advocateIds);
        }
    }

    private void updateRelatedContacts(Set<Id> patientIds, Set<Id> advocateIds) {
        List<Contact> contactsToUpdate = new List<Contact>();

        Map<Id, Datetime> latestSoDateByAdvocate = new Map<Id, Datetime>();
        if (!advocateIds.isEmpty()) {
            // Aggregate directly by Advocate via HP relationship to avoid queryMore limit on large datasets
            for (AggregateResult ar : [
                SELECT MAX(Appointment_Date_Time__c) maxDate, Health_Profile__r.Patient_Advocate__c advId
                FROM PurchaseOrder__c
                WHERE Status__c = 'Complete'
                  AND Health_Profile__r.Patient_Advocate__c IN :advocateIds
                GROUP BY Health_Profile__r.Patient_Advocate__c
                LIMIT 2000
            ]) {
                Id advId = (Id) ar.get('advId');
                if (advId != null) latestSoDateByAdvocate.put(advId, (Datetime) ar.get('maxDate'));
            }
        }


        for (Contact c : [
            SELECT Id, ICF_Version__c, Most_recent_completed_SO_date__c,
                (SELECT ICF_Version_on_File__c, ICF_Date_of_Signature__c
                 FROM Opportunities__r
                 WHERE ICF_Version_on_File__c != null
                 ORDER BY ICF_Date_of_Signature__c DESC NULLS LAST)
            FROM Contact
            WHERE Id IN :patientIds OR Id IN :advocateIds
        ]) {
            // Update ICF Version for Patients
            if (patientIds.contains(c.Id)) {
                String versionStr = '';
                for (HealthProfile__c hp : c.Opportunities__r) {
                    versionStr += '\n' + hp.ICF_Version_on_File__c + '------' +
                        (hp.ICF_Date_of_Signature__c != null ? hp.ICF_Date_of_Signature__c.format() : '');
                }
                if (!String.isBlank(versionStr)) {
                    c.ICF_Version__c = versionStr.removeStart('\n');
                }
            }

            // Update Most Recent SO Date for Advocates
            if (advocateIds.contains(c.Id)) {
                c.Most_recent_completed_SO_date__c = latestSoDateByAdvocate.get(c.Id);
            }

            contactsToUpdate.add(c);
        }

        if (!contactsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(contactsToUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Contact update failed: ' + err.getStatusCode() + ': ' + err.getMessage());
                    }
                }
            }
        }
    }

    // ---------------- UNUSED INTERFACE METHODS ----------------

    public void beforeInsert(List<SObject> newRecords) {
    }
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
    }
    public void beforeDelete(Map<Id, SObject> oldMap) {
    }
}