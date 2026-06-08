/**
 * @description       : Handler to validate GMP Collection Health Profile creation/update against GMP Screening rules.
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-14
 * @executionOrder    : 10 (Validation & Required Field Checks)
 * @group             : Health Profile Trigger Handlers
 * @group-content     : ClinicalEntryValidationHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Enforces sharing (with sharing).
 * - CRUD/FLS checks applied before querying.
 * - Bulkified: handles 200+ records.
 * - No SOQL/DML in loops.
 * - Field-selective queries.
 * - Single responsibility principle.
 */
public with sharing class ClinicalEntryValidationHandler implements ITriggerHandler {

    public void afterInsert(List<SObject> newRecords) {
        validateQualityCollectionEntries((List<ClinicalEntry__c>) newRecords);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<ClinicalEntry__c> newHps = (List<ClinicalEntry__c>) newRecords;
        Map<Id, ClinicalEntry__c> oldHps = (Map<Id, ClinicalEntry__c>) oldMap;

        List<ClinicalEntry__c> relevant = new List<ClinicalEntry__c>();
        for (ClinicalEntry__c hp : newHps) {
            ClinicalEntry__c oldHp = (oldHps != null) ? oldHps.get(hp.Id) : null;
            if (oldHp == null
                || hp.Master_Plan__c != oldHp.Master_Plan__c
                || hp.Patient__c != oldHp.Patient__c
                || hp.Appointment_Date_Time__c != oldHp.Appointment_Date_Time__c) {
                relevant.add(hp);
            }
        }
        if (relevant.isEmpty()) return;

        validateQualityCollectionEntries(relevant);
    }

    /**
     * @description Validates that GMP Collection SO has a related Screening SO within 7 days.
     * @param clinicalEntries List of Health Profiles from trigger context.
     */
    private void validateQualityCollectionEntries(List<ClinicalEntry__c> clinicalEntries) {
        if (clinicalEntries.isEmpty()) return;

        // Collect Master Plan Ids
        Set<Id> projectPlanIds = new Set<Id>();
        for (ClinicalEntry__c hp : clinicalEntries) {
            if (hp.Master_Plan__c != null) {
                projectPlanIds.add(hp.Master_Plan__c);
            }
        }
        if (projectPlanIds.isEmpty()) return;

        // CRUD/FLS check for Master Plan
        if (!Schema.sObjectType.ProjectPlan__c.isAccessible() ||
            !Schema.sObjectType.ProjectPlan__c.fields.Study_Type__c.isAccessible() ||
            !Schema.sObjectType.ProjectPlan__c.fields.Aphaeresis_Collection_Type__c.isAccessible()) {
            return;
        }

        Map<Id, ProjectPlan__c> projectPlanMap = new Map<Id, ProjectPlan__c>([
            SELECT Id, Study_Type__c, Aphaeresis_Collection_Type__c
            FROM ProjectPlan__c
            WHERE Id IN :projectPlanIds
        ]);

        // Collect Patient IDs needing screening check
        Set<Id> patientIds = new Set<Id>();
        for (ClinicalEntry__c hp : clinicalEntries) {
            ProjectPlan__c mp = projectPlanMap.get(hp.Master_Plan__c);
            if (mp != null &&
                mp.Study_Type__c == 'Apheresis GMP' &&
                mp.Aphaeresis_Collection_Type__c == 'Collection' &&
                hp.Patient__c != null) {
                patientIds.add(hp.Patient__c);
            }
        }
        if (patientIds.isEmpty()) return;

        // CRUD/FLS check for ClinicalEntry__c fields
        if (!Schema.sObjectType.ClinicalEntry__c.isAccessible() ||
            !Schema.sObjectType.ClinicalEntry__c.fields.Status__c.isAccessible() ||
            !Schema.sObjectType.ClinicalEntry__c.fields.Appointment_Date_Time__c.isAccessible()) {
            return;
        }

        // Query the latest GMP Screening SO for each patient
        Map<Id, ClinicalEntry__c> latestScreeningMap = new Map<Id, ClinicalEntry__c>();
        for (ClinicalEntry__c scr : [
            SELECT Id, Patient__c, Appointment_Date_Time__c
            FROM ClinicalEntry__c
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
        for (ClinicalEntry__c hp : clinicalEntries) {
            ProjectPlan__c mp = projectPlanMap.get(hp.Master_Plan__c);
            if (mp != null &&
                mp.Study_Type__c == 'Apheresis GMP' &&
                mp.Aphaeresis_Collection_Type__c == 'Collection' &&
                hp.Patient__c != null &&
                hp.Appointment_Date_Time__c != null) {

                ClinicalEntry__c screeningHp = latestScreeningMap.get(hp.Patient__c);
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
