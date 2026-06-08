/**
 * @description       : Handler to validate GMP Collection Health Profile creation/update against GMP Screening rules.
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-14
 * @executionOrder    : 10 (Validation & Required Field Checks)
 * @group             : Health Profile Trigger Handlers
 * @group-content     : HealthProfileGMPValidationHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Enforces sharing (with sharing).
 * - CRUD/FLS checks applied before querying.
 * - Bulkified: handles 200+ records.
 * - No SOQL/DML in loops.
 * - Field-selective queries.
 * - Single responsibility principle.
 */
public with sharing class HealthProfileGMPValidationHandler implements ITriggerHandler {

    public void afterInsert(List<SObject> newRecords) {
        validateGmpCollectionHealthProfiles((List<HealthProfile__c>) newRecords);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<HealthProfile__c> newHps = (List<HealthProfile__c>) newRecords;
        Map<Id, HealthProfile__c> oldHps = (Map<Id, HealthProfile__c>) oldMap;

        List<HealthProfile__c> relevant = new List<HealthProfile__c>();
        for (HealthProfile__c hp : newHps) {
            HealthProfile__c oldHp = (oldHps != null) ? oldHps.get(hp.Id) : null;
            if (oldHp == null
                || hp.Master_Plan__c != oldHp.Master_Plan__c
                || hp.Patient__c != oldHp.Patient__c
                || hp.Appointment_Date_Time__c != oldHp.Appointment_Date_Time__c) {
                relevant.add(hp);
            }
        }
        if (relevant.isEmpty()) return;

        validateGmpCollectionHealthProfiles(relevant);
    }

    /**
     * @description Validates that GMP Collection SO has a related Screening SO within 7 days.
     * @param healthProfiles List of Health Profiles from trigger context.
     */
    private void validateGmpCollectionHealthProfiles(List<HealthProfile__c> healthProfiles) {
        if (healthProfiles.isEmpty()) return;

        // Collect Master Plan Ids
        Set<Id> masterPlanIds = new Set<Id>();
        for (HealthProfile__c hp : healthProfiles) {
            if (hp.Master_Plan__c != null) {
                masterPlanIds.add(hp.Master_Plan__c);
            }
        }
        if (masterPlanIds.isEmpty()) return;

        // CRUD/FLS check for Master Plan
        if (!Schema.sObjectType.MasterPlan__c.isAccessible() ||
            !Schema.sObjectType.MasterPlan__c.fields.Study_Type__c.isAccessible() ||
            !Schema.sObjectType.MasterPlan__c.fields.Aphaeresis_Collection_Type__c.isAccessible()) {
            return;
        }

        Map<Id, MasterPlan__c> masterPlanMap = new Map<Id, MasterPlan__c>([
            SELECT Id, Study_Type__c, Aphaeresis_Collection_Type__c
            FROM MasterPlan__c
            WHERE Id IN :masterPlanIds
        ]);

        // Collect Patient IDs needing screening check
        Set<Id> patientIds = new Set<Id>();
        for (HealthProfile__c hp : healthProfiles) {
            MasterPlan__c mp = masterPlanMap.get(hp.Master_Plan__c);
            if (mp != null &&
                mp.Study_Type__c == 'Apheresis GMP' &&
                mp.Aphaeresis_Collection_Type__c == 'Collection' &&
                hp.Patient__c != null) {
                patientIds.add(hp.Patient__c);
            }
        }
        if (patientIds.isEmpty()) return;

        // CRUD/FLS check for HealthProfile__c fields
        if (!Schema.sObjectType.HealthProfile__c.isAccessible() ||
            !Schema.sObjectType.HealthProfile__c.fields.Status__c.isAccessible() ||
            !Schema.sObjectType.HealthProfile__c.fields.Appointment_Date_Time__c.isAccessible()) {
            return;
        }

        // Query the latest GMP Screening SO for each patient
        Map<Id, HealthProfile__c> latestScreeningMap = new Map<Id, HealthProfile__c>();
        for (HealthProfile__c scr : [
            SELECT Id, Patient__c, Appointment_Date_Time__c
            FROM HealthProfile__c
            WHERE (Status__c = 'Donated Blood'
                OR Status__c = 'Appointment Scheduled (Screening)')
            AND Patient__c IN :patientIds
            AND Master_Plan__r.Study_Type__c = 'Apheresis GMP'
            AND Master_Plan__r.Aphaeresis_Collection_Type__c = 'Screening'
            ORDER BY Appointment_Date_Time__c DESC
        ]) {
            if (!latestScreeningMap.containsKey(scr.Patient__c)) {
                latestScreeningMap.put(scr.Patient__c, scr);
            }
        }

        // Validate date difference:
        for (HealthProfile__c hp : healthProfiles) {
            MasterPlan__c mp = masterPlanMap.get(hp.Master_Plan__c);
            if (mp != null &&
                mp.Study_Type__c == 'Apheresis GMP' &&
                mp.Aphaeresis_Collection_Type__c == 'Collection' &&
                hp.Patient__c != null &&
                hp.Appointment_Date_Time__c != null) {

                HealthProfile__c screeningHp = latestScreeningMap.get(hp.Patient__c);
                if (screeningHp != null && screeningHp.Appointment_Date_Time__c != null) {
                    Integer daysDiff = screeningHp.Appointment_Date_Time__c.date()
                        .daysBetween(hp.Appointment_Date_Time__c.date());
                    if (daysDiff > 7) {
                        hp.addError('You cannot create or update this GMP Collection SO because the related GMP Screening SO was completed more than 7 days ago.');
                    }
                }
            }
        }
    }

    // Empty interface methods
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
