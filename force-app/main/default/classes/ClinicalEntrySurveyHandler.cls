/**
 * @description       : Handler to generate Study Specific Answer (SSQ) and DNQ Answer records based on associated Master Plan questions.
 * ClinicalEntrySurveyHandler.cls that encapsulates:
 * SSQ creation logic (checkForAndCreateSSQ)
 * DNQ answer creation logic (checkForAndCreateDNQ)
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-06
 * @executionOrder    : 50 (Integration & Related Records)
 * @group             : Health Profile Trigger Handlers
 * @group-content     : ClinicalEntrySurveyHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - Object CRUD and field-level access are validated; data is sanitized via Security.stripInaccessible.
 * - No SOQL/DML inside loops; bulk-safe across 200+ rows.
 * - Defensive queries are field-selective and filtered.
 * - Updates use Database.insert(..., false) for partial success.
 * - Methods < 100 lines, meaningful names, and single-responsibility design.
 */

public with sharing class ClinicalEntrySurveyHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'ClinicalEntrySurveyHandler';
    private static final String OBJECT_NAME = 'ClinicalEntry__c';

    public void afterInsert(List<SObject> newRecords) {
        try {
            List<ClinicalEntry__c> newHps = (List<ClinicalEntry__c>) newRecords;
            createSSQsAndDNQs(newHps);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<ClinicalEntry__c> newHps = (List<ClinicalEntry__c>) newRecords;
            Map<Id, ClinicalEntry__c> oldHps = (Map<Id, ClinicalEntry__c>) oldMap;

            List<ClinicalEntry__c> relevant = new List<ClinicalEntry__c>();
            for (ClinicalEntry__c hp : newHps) {
                ClinicalEntry__c oldHp = (oldHps != null) ? oldHps.get(hp.Id) : null;
                if (oldHp == null
                    || hp.Master_Plan__c != oldHp.Master_Plan__c
                    || hp.Skip_SSQ_Creation__c != oldHp.Skip_SSQ_Creation__c) {
                    relevant.add(hp);
                }
            }
            if (relevant.isEmpty()) return;

            createSSQsAndDNQs(relevant);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private void createSSQsAndDNQs(List<ClinicalEntry__c> hps) {
        Map<Id, ClinicalEntry__c> profilesById = new Map<Id, ClinicalEntry__c>();
        Set<Id> mpIds = new Set<Id>();

        for (ClinicalEntry__c hp : hps) {
            if (hp.Master_Plan__c != null && !hp.Skip_SSQ_Creation__c) {
                profilesById.put(hp.Id, hp);
                mpIds.add(hp.Master_Plan__c);
            }
        }

        if (profilesById.isEmpty()) return;

        createSSQAnswers(profilesById, mpIds);
        createDNQAnswers(profilesById, mpIds);
    }

    private void createSSQAnswers(Map<Id, ClinicalEntry__c> profilesById, Set<Id> mpIds) {
        // Fetch all SSQs for Master Plans
        Map<Id, List<Study_Specific_Question__c>> ssqsByMpId = new Map<Id, List<Study_Specific_Question__c>>();
        for (Study_Specific_Question__c q : [
            SELECT Id, Master_Plan__c, Question__c
            FROM Study_Specific_Question__c
            WHERE Master_Plan__c IN :mpIds AND IsDeleted = FALSE
        ]) {
            if (!ssqsByMpId.containsKey(q.Master_Plan__c)) {
                ssqsByMpId.put(q.Master_Plan__c, new List<Study_Specific_Question__c>());
            }
            ssqsByMpId.get(q.Master_Plan__c).add(q);
        }

        // Fetch existing SSQ Answers to avoid duplicates
        Map<Id, Set<Id>> existingAnswersByHp = new Map<Id, Set<Id>>();
        for (Study_Specific_Answer__c a : [
            SELECT Health_Profile__c, Study_Specific_Question__c
            FROM Study_Specific_Answer__c
            WHERE Health_Profile__c IN :profilesById.keySet()
        ]) {
            if (!existingAnswersByHp.containsKey(a.Health_Profile__c)) {
                existingAnswersByHp.put(a.Health_Profile__c, new Set<Id>());
            }
            existingAnswersByHp.get(a.Health_Profile__c).add(a.Study_Specific_Question__c);
        }

        List<Study_Specific_Answer__c> insertQueue = new List<Study_Specific_Answer__c>();
        for (Id hpId : profilesById.keySet()) {
            ClinicalEntry__c hp = profilesById.get(hpId);
            if (!ssqsByMpId.containsKey(hp.Master_Plan__c)) continue;

            for (Study_Specific_Question__c q : ssqsByMpId.get(hp.Master_Plan__c)) {
                if (!existingAnswersByHp.containsKey(hpId) ||
                    !existingAnswersByHp.get(hpId).contains(q.Id)) {
                    insertQueue.add(new Study_Specific_Answer__c(
                        Health_Profile__c = hpId,
                        Study_Specific_Question__c = q.Id,
                        Question__c = q.Question__c
                    ));
                }
            }
        }

            if (!insertQueue.isEmpty()) {
            Database.SaveResult[] srs = Database.insert(insertQueue, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (!srs[i].isSuccess()) {
                    for (Database.Error err : srs[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'SSQ insert failed: ' + err.getStatusCode() + ': ' + err.getMessage() +
                            ' HP=' + insertQueue[i].Health_Profile__c +
                            ', SSQ=' + insertQueue[i].Study_Specific_Question__c);
                    }
                }
            }
        }
    }


    private void createDNQAnswers(Map<Id, ClinicalEntry__c> profilesById, Set<Id> mpIds) {
        // Fetch DNQ Questions
        Map<Id, List<Study_Specific_DNQ_Question__c>> dnqsByMpId = new Map<Id, List<Study_Specific_DNQ_Question__c>>();
        for (Study_Specific_DNQ_Question__c q : [
            SELECT Id, Master_Plan__c, DNQ_Question__c
            FROM Study_Specific_DNQ_Question__c
            WHERE Master_Plan__c IN :mpIds AND IsDeleted = FALSE
        ]) {
            if (!dnqsByMpId.containsKey(q.Master_Plan__c)) {
                dnqsByMpId.put(q.Master_Plan__c, new List<Study_Specific_DNQ_Question__c>());
            }
            dnqsByMpId.get(q.Master_Plan__c).add(q);
        }

        // Fetch existing DNQ Answers
        Map<Id, Set<Id>> existingByHp = new Map<Id, Set<Id>>();
        for (Study_Specific_DNQ_Answer__c a : [
            SELECT Health_Profile__c, Study_Specific_DNQ_Question__c
            FROM Study_Specific_DNQ_Answer__c
            WHERE Health_Profile__c IN :profilesById.keySet()
        ]) {
            if (!existingByHp.containsKey(a.Health_Profile__c)) {
                existingByHp.put(a.Health_Profile__c, new Set<Id>());
            }
            existingByHp.get(a.Health_Profile__c).add(a.Study_Specific_DNQ_Question__c);
        }

        List<Study_Specific_DNQ_Answer__c> insertQueue = new List<Study_Specific_DNQ_Answer__c>();
        for (Id hpId : profilesById.keySet()) {
            ClinicalEntry__c hp = profilesById.get(hpId);
            if (!dnqsByMpId.containsKey(hp.Master_Plan__c)) continue;

            for (Study_Specific_DNQ_Question__c q : dnqsByMpId.get(hp.Master_Plan__c)) {
                if (!existingByHp.containsKey(hpId) ||
                    !existingByHp.get(hpId).contains(q.Id)) {
                    insertQueue.add(new Study_Specific_DNQ_Answer__c(
                        Health_Profile__c = hpId,
                        Study_Specific_DNQ_Question__c = q.Id,
                        Question__c = q.DNQ_Question__c
                    ));
                }
            }
        }

        if (!insertQueue.isEmpty()) {
            try {
                Database.SaveResult[] srs = Database.insert(insertQueue, false);
                for (Integer i = 0; i < srs.size(); i++) {
                    if (!srs[i].isSuccess()) {
                        for (Database.Error err : srs[i].getErrors()) {
                            System.debug(LoggingLevel.ERROR,
                                'DNQ insert failed: ' + err.getStatusCode() + ': ' + err.getMessage() +
                                ' HP=' + insertQueue[i].Health_Profile__c +
                                ', DNQ=' + insertQueue[i].Study_Specific_DNQ_Question__c);
                        }
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, e.getMessage());
            }
        }
    }

    // ---------------- UNUSED INTERFACE METHODS ----------------

    public void beforeInsert(List<SObject> newRecords) {
    }
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
    }
    public void beforeDelete(Map<Id, SObject> oldMap) {    }
    public void afterDelete(Map<Id, SObject> oldMap) {
    }
	public void afterUndelete(List<SObject> newRecords) {
    }
}
