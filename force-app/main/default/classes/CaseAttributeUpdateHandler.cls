/**
 * @description       : FIELD UPDATE handler for Case (links Opportunity__c via Project_Plan__c).
 * @executionOrder    : 30 (Field Defaults & Updates)
 * @notes             : Preserves legacy quirk — beforeUpdate ignores oldMap and passes null logic.
 * @author            : Refactor: S.M. Akbar
 */
public without sharing class CaseAttributeUpdateHandler implements ITriggerHandler {

    public void beforeInsert(List<SObject> newRecords) {
        updateCaseFields((List<Case>) newRecords, null);
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        // IMPORTANT: legacy behavior intentionally ignores oldMap
        updateCaseFields((List<Case>) newRecords, null);
    }

    // Unused phases (no-op for parity)
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}

    // ---------- Legacy-equivalent logic (scoped private) ----------
    private static void updateCaseFields(List<Case> recList, Map<Id, Case> oldRec) {
        Set<Id> projectPlanIds = new Set<Id>();
        List<Case> recordsToProcess = new List<Case>();

        for (Case c : recList) {
            if ((oldRec == null && c.Project_Plan__c != null) ||
                (oldRec != null && c.Project_Plan__c != oldRec.get(c.Id).Project_Plan__c)) {

                if (c.Project_Plan__c != null) {
                    projectPlanIds.add(c.Project_Plan__c);
                    recordsToProcess.add(c);
                } else {
                    c.Opportunity__c = null;
                }
            }
        }

        if (!projectPlanIds.isEmpty()) {
            Map<Id, ProjectPlan__c> mplanMap = new Map<Id, ProjectPlan__c>(
                [SELECT Id, Opportunity__c FROM ProjectPlan__c WHERE Id IN :projectPlanIds]
            );
            for (Case c : recordsToProcess) {
                if (c.Project_Plan__c != null && mplanMap.containsKey(c.Project_Plan__c)) {
                    c.Opportunity__c = mplanMap.get(c.Project_Plan__c).Opportunity__c;
                }
            }
        }
    }
}
