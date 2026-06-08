/**
 * @description       : AFTER UPDATE business sequence (post-cleanup):
 * 1) Auto-approve custom Criterion__c when Stage 2 → Stage 3 transition occurs.
 * (Note: logic for handling AccountId population → lead conversion / OCR creation was removed as requested.
 *        Prior CSM__c propagation to Master Plans is also removed.)
 *
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-28
 * @executionOrder    : 55 (Complex Business Logic)
 * @group             : Opportunity Trigger Handlers
 * @group-content     : OpportunityAfterUpdateBusinessHandler.cls
 */
public with sharing class OpportunityAfterUpdateBusinessHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'OpportunityAfterUpdateBusinessHandler';
    private static final String OPP_STAGE_2 = 'Stage 2 - SRF Complete/Feasibility Review';
    private static final String OPP_STAGE_3 = 'Stage 3 - Feasibility Approved/Proposal Delivery';

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        try {
            List<Opportunity> opps = (List<Opportunity>) newRecords;
            approveCustomIECriteria(opps, (Map<Id, Opportunity>) oldMap);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private static void approveCustomIECriteria(List<Opportunity> opps, Map<Id, Opportunity> oldMap) {
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : opps) {
            Opportunity oldOpp = oldMap.get(o.Id);
            if (oldOpp == null) continue;
            if (oldOpp.StageName == OPP_STAGE_2 && o.StageName == OPP_STAGE_3) { oppIds.add(o.Id); }
        }
        if (oppIds.isEmpty()) return;

        List<Criterion__c> approvalQueue = new List<Criterion__c>();
        for (Criterion__c c : [
            SELECT Id, Status__c
            FROM Criterion__c
            WHERE Is_Custom__c = true
              AND Status__c != 'Approved'
              AND Opportunity__c IN :oppIds
        ]) {
            c.Status__c = 'Approved';
            approvalQueue.add(c);
        }
        if (!approvalQueue.isEmpty()) {
            try { Database.update(approvalQueue, false); }
            catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, e.getMessage());
            }
        }
    }

    // Unused
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
