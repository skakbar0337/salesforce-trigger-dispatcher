/**
 * @description       : ROLLUP handler for Master Plans based on Case changes (error/type/impact).
 * @executionOrder    : 70 (Roll-ups & Calculations)
 * @notes             : Preserves skip rule: if Phlebotomist__c is null AND Lev_1_Responsible_Party__c
 *                      in {'Study participant','Partner-contracted specialist'}, skip counting that Case.
 *                      Delete/Undelete parity retained (old vs new lists).
 * @author            : Refactor: S.M. Akbar
 */
public without sharing class CasePlanErrorAggregateHandler implements ITriggerHandler {

    public void afterInsert(List<SObject> newRecords) {
        rollupProjectPlans((List<Case>) newRecords, null);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        rollupProjectPlans((List<Case>) newRecords, (Map<Id, Case>) oldMap);
    }

    public void afterDelete(Map<Id, SObject> oldMap) {
        rollupProjectPlans(castToCases(oldMap), null);
    }

    public void afterUndelete(List<SObject> newRecords) {
        rollupProjectPlans((List<Case>) newRecords, null);
    }

    // Unused phases
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}

    // ---------- Legacy-equivalent logic (scoped private) ----------

    private static List<Case> castToCases(Map<Id, SObject> m) {
        List<Case> out = new List<Case>();
        if (m != null) {
            for (SObject s : m.values()) out.add((Case) s);
        }
        return out;
    }

    private static void rollupProjectPlans(List<Case> recList, Map<Id, Case> oldRec) {
        Set<Id> projectPlanId = new Set<Id>();

        for (Case c : recList) {
            // Skip rule (unchanged)
            if (c.Phlebotomist__c == null &&
               (c.Lev_1_Responsible_Party__c == 'Study participant' ||
                c.Lev_1_Responsible_Party__c == 'Partner-contracted specialist')) {
                continue;
            }

            if ((oldRec == null && c.Master_Plan__c != null) ||
                (oldRec != null && (
                    c.Master_Plan__c   != oldRec.get(c.Id).Master_Plan__c ||
                    c.Error_Source__c  != oldRec.get(c.Id).Error_Source__c ||
                    c.Error_Type__c    != oldRec.get(c.Id).Error_Type__c ||
                    c.Impact_Effect__c != oldRec.get(c.Id).Impact_Effect__c
                ))) {

                if (oldRec != null && c.Master_Plan__c != oldRec.get(c.Id).Master_Plan__c) {
                    projectPlanId.add(oldRec.get(c.Id).Master_Plan__c);
                }
                if (c.Master_Plan__c != null) {
                    projectPlanId.add(c.Master_Plan__c);
                }
            }
        }

        if (!projectPlanId.isEmpty()) {
            updateProjectPlans(projectPlanId);
        }
    }

    private static void updateProjectPlans(Set<Id> projectPlanId) {
        Map<Id, Map<String, Integer>> bySource  = new Map<Id, Map<String, Integer>>();
        Map<Id, Map<String, Integer>> byType    = new Map<Id, Map<String, Integer>>();
        Map<Id, Map<String, Integer>> byImpact  = new Map<Id, Map<String, Integer>>();

        // --- Error Type counts ---
        for (AggregateResult ag : [
            SELECT COUNT(Id) counter, Master_Plan__c mp, Error_Type__c etype
            FROM Case
            WHERE Master_Plan__c IN :projectPlanId
            GROUP BY Master_Plan__c, Error_Type__c
        ]) {
            Id idKey = (Id) ag.get('mp');
            if (!byType.containsKey(idKey)) {
                byType.put(idKey, new Map<String, Integer>());
            }
            byType.get(idKey).put(String.valueOf(ag.get('etype')),
                                  Integer.valueOf(ag.get('counter')));
        }

        // --- Error Source counts ---
        for (AggregateResult ag : [
            SELECT COUNT(Id) counter, Master_Plan__c mp, Error_Source__c source
            FROM Case
            WHERE Master_Plan__c IN :projectPlanId
            GROUP BY Master_Plan__c, Error_Source__c
        ]) {
            Id idKey = (Id) ag.get('mp');
            if (!bySource.containsKey(idKey)) {
                bySource.put(idKey, new Map<String, Integer>());
            }
            bySource.get(idKey).put(String.valueOf(ag.get('source')),
                                    Integer.valueOf(ag.get('counter')));
        }

        // --- Impact Effect counts ---
        for (AggregateResult ag : [
            SELECT COUNT(Id) counter, Master_Plan__c mp, Impact_Effect__c impactEffect
            FROM Case
            WHERE Master_Plan__c IN :projectPlanId
            GROUP BY Master_Plan__c, Impact_Effect__c
        ]) {
            Id idKey = (Id) ag.get('mp');
            if (!byImpact.containsKey(idKey)) {
                byImpact.put(idKey, new Map<String, Integer>());
            }
            byImpact.get(idKey).put(String.valueOf(ag.get('impactEffect')),
                                    Integer.valueOf(ag.get('counter')));
        }

        Map<Id, ProjectPlan__c> mplanMap = new Map<Id, ProjectPlan__c>();

        for (Id i : projectPlanId) {
            ProjectPlan__c mp = new ProjectPlan__c(Id = i);

            // Error Source rollups
            mp.Error_Source_Phlebotomist__c =
                bySource.containsKey(i) && bySource.get(i).containsKey('Phlebotomist')
                ? bySource.get(i).get('Phlebotomist') : 0;
            mp.Error_Source_Client__c =
                bySource.containsKey(i) && bySource.get(i).containsKey('Client')
                ? bySource.get(i).get('Client') : 0;
            mp.Error_Source_Internal__c =
                bySource.containsKey(i) && bySource.get(i).containsKey('Internal')
                ? bySource.get(i).get('Internal') : 0;
            mp.Error_Source_FedEx__c =
                bySource.containsKey(i) && bySource.get(i).containsKey('FedEx')
                ? bySource.get(i).get('FedEx') : 0;
            mp.Error_Source_Lab__c =
                bySource.containsKey(i) && bySource.get(i).containsKey('Lab')
                ? bySource.get(i).get('Lab') : 0;
            mp.Error_Source_Acts_of_God__c =
                bySource.containsKey(i) && bySource.get(i).containsKey('Acts of God')
                ? bySource.get(i).get('Acts of God') : 0;

            // Error Type rollups (exact sums)
            mp.Error_Type_Sample_Error__c =
                (byType.containsKey(i) ? (
                    (byType.get(i).containsKey('Sample error - blood collection') ? byType.get(i).get('Sample error - blood collection') : 0) +
                    (byType.get(i).containsKey('Sample error - processing')       ? byType.get(i).get('Sample error - processing')       : 0) +
                    (byType.get(i).containsKey('Sample error - labeling/forms')   ? byType.get(i).get('Sample error - labeling/forms')   : 0)
                ) : 0);

            mp.Error_Type_Shipping_Error__c =
                (byType.containsKey(i) ? (
                    (byType.get(i).containsKey('Shipping error - supply')   ? byType.get(i).get('Shipping error - supply')   : 0) +
                    (byType.get(i).containsKey('Shipping error - specimen') ? byType.get(i).get('Shipping error - specimen') : 0)
                ) : 0);

            mp.Error_Type_Administrative_Error__c =
                byType.containsKey(i) && byType.get(i).containsKey('Administrative Error')
                ? byType.get(i).get('Administrative Error') : 0;
            mp.Error_Type_Appointment_Error__c =
                byType.containsKey(i) && byType.get(i).containsKey('Appointment error - reschedule/cancellation')
                ? byType.get(i).get('Appointment error - reschedule/cancellation') : 0;
            mp.Error_Type_Other__c =
                byType.containsKey(i) && byType.get(i).containsKey('Other')
                ? byType.get(i).get('Other') : 0;

            // Impact Effect rollups
            mp.Client_Facing_Impact__c =
                byImpact.containsKey(i) && byImpact.get(i).containsKey('Client-Facing Impact')
                ? byImpact.get(i).get('Client-Facing Impact') : 0;
            mp.Internal_Impact__c =
                byImpact.containsKey(i) && byImpact.get(i).containsKey('Internal Impact')
                ? byImpact.get(i).get('Internal Impact') : 0;

            mplanMap.put(i, mp);
        }

        if (!mplanMap.isEmpty()) {
            Database.update(mplanMap.values());
        }
    }
}