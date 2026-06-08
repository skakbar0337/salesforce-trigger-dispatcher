/**
 * @description       : ROLLUP to Opportunity.Number_of_cases__c across all Master Plans under the Opportunity.
 *                      This preserves 1:1 behavior with the legacy Case trigger helper's "findOpportunitiesToUpdate".
 * @executionOrder    : 75 (Roll-ups & Calculations) — runs after MP rollups for stable ordering
 * @notes             : - No CRUD/FLS gates to keep exact parity with trigger behavior.
 *                      - 'without sharing' to mirror trigger/system mode execution.
 *                      - Bulkified; no SOQL/DML in loops.
 * @author            : S.M Akbar
 */
public without sharing class CaseOppCountHandler implements ITriggerHandler {

    // ---------------- ITriggerHandler entry points ----------------

    public void afterInsert(List<SObject> newRecords) {
        List<Case> cases = toCaseList(newRecords);
        recalcOpportunityCaseCount(cases, null);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<Case> cases = toCaseList(newRecords);
        Map<Id, Case> oldCases = toCaseMap(oldMap);
        recalcOpportunityCaseCount(cases, oldCases);
    }

    public void afterDelete(Map<Id, SObject> oldMap) {
        List<Case> deletedCases = toCaseList(oldMap);
        // Legacy path passes records with old values and NULL oldMap
        recalcOpportunityCaseCount(deletedCases, null);
    }

    public void afterUndelete(List<SObject> newRecords) {
        List<Case> cases = toCaseList(newRecords);
        recalcOpportunityCaseCount(cases, null);
    }

    // Unused phases (intentionally empty to keep behavior clear & modular)
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}

    // ---------------- Private implementation (parity with legacy) ----------------

    /**
     * @description Recalculate Opportunity.Number_of_cases__c for Opportunities related to changed Master Plans.
     *              Exact legacy logic:
     *              - Identify Master Plans from current (and old, if changed) Case.Project_Plan__c.
     *              - Collect their Opportunities.
     *              - Count Cases grouped by Project_Plan__r.Opportunity__c.
     *              - Update Number_of_cases__c with counts; set to 0 where no Cases remain.
     */
    private static void recalcOpportunityCaseCount(List<Case> recList, Map<Id, Case> oldRec) {
        if (recList == null || recList.isEmpty()) return;

        // 1) Determine Master Plans touched by these Cases (current and/or previous MP)
        Set<Id> projectPlanIds = new Set<Id>();
        for (Case c : recList) {
            if ((oldRec == null && c.Project_Plan__c != null) ||
                (oldRec != null && c.Project_Plan__c != oldRec.get(c.Id).Project_Plan__c)) {

                if (c.Project_Plan__c != null) {
                    projectPlanIds.add(c.Project_Plan__c);
                }
                if (oldRec != null) {
                    Case oldC = oldRec.get(c.Id);
                    if (oldC != null && oldC.Project_Plan__c != null) {
                        projectPlanIds.add(oldC.Project_Plan__c);
                    }
                }
            }
        }
        if (projectPlanIds.isEmpty()) return;

        // 2) Collect Opportunity Ids from those Master Plans
        Set<Id> oppIds = new Set<Id>();
        for (ProjectPlan__c mp : [
            SELECT Opportunity__c
            FROM ProjectPlan__c
            WHERE Id IN :projectPlanIds AND Opportunity__c != null
        ]) {
            oppIds.add(mp.Opportunity__c);
        }
        if (oppIds.isEmpty()) return;

        // 3) Aggregate Case count per Opportunity (across all master plans under that opp)
        Map<Id, Opportunity> oppToUpdate = new Map<Id, Opportunity>();
        for (AggregateResult ar : [
            SELECT COUNT(Id) counter, Project_Plan__r.Opportunity__c opp
            FROM Case
            WHERE Project_Plan__r.Opportunity__c IN :oppIds
            GROUP BY Project_Plan__r.Opportunity__c
        ]) {
            Opportunity o = new Opportunity(
                Id = (Id) ar.get('opp'),
                Number_of_cases__c = (Decimal) ar.get('counter')
            );
            oppToUpdate.put(o.Id, o);
        }

        // 4) For any Opportunity we touched but didn't see in aggregation, set the count to 0
        for (Id oppId : oppIds) {
            if (!oppToUpdate.containsKey(oppId)) {
                oppToUpdate.put(oppId, new Opportunity(Id = oppId, Number_of_cases__c = 0));
            }
        }

        if (!oppToUpdate.isEmpty()) {
            Database.update(oppToUpdate.values());
        }
    }

    // ---------------- Casting helpers (to avoid unsafe generic casts) ----------------

    private static List<Case> toCaseList(List<SObject> sobs) {
        List<Case> out = new List<Case>();
        if (sobs != null) {
            for (SObject so : sobs) out.add((Case) so);
        }
        return out;
    }

    private static List<Case> toCaseList(Map<Id, SObject> m) {
        List<Case> out = new List<Case>();
        if (m != null && !m.isEmpty()) {
            for (SObject so : m.values()) out.add((Case) so);
        }
        return out;
    }

    private static Map<Id, Case> toCaseMap(Map<Id, SObject> m) {
        Map<Id, Case> out = new Map<Id, Case>();
        if (m != null && !m.isEmpty()) {
            for (Id keyId : m.keySet()) {
                out.put(keyId, (Case) m.get(keyId));
            }
        }
        return out;
    }
}
