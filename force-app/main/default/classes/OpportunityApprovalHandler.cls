/**
 * @description       : Validates Feasibility Approval step fields when the related checkboxes are unchecked by the process.
 * Ensures required values (Lab Startup Period / Recruitment Startup Period) are present at the correct step transitions.
 * Pure validation; no DML. Preserves legacy behavior from OpportunityTriggerHelper.doBeforeUpdate().
 * @author            : Refactored by S.M Akbar
 * @date              : 2025-08-28
 * @executionOrder    : 10 (Validation & Required Field Checks)
 * @group             : Opportunity Trigger Handlers
 * @group-content     : OpportunityApprovalHandler.cls
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - No CRUD/FLS changes are performed; only addError() validations.
 * - Bulk-safe, no SOQL/DML, zero side effects; methods < 100 lines.
 * - Clear separation of concerns; single-responsibility validation handler.
 */

public with sharing class OpportunityApprovalHandler implements ITriggerHandler {
    // Local constants used only here
    private static final String ERR_LAB  = 'Please enter a non-blank value for "Lab Startup Period".';
    private static final String ERR_REC  = 'Please enter a non-blank value for "Recruitment Startup Period".';

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        validateApprovalFields((List<Opportunity>) newRecords, (Map<Id, Opportunity>) oldMap);
    }

    private static void validateApprovalFields(List<Opportunity> updatedOpps, Map<Id, Opportunity> oldMap) {
    List<Opportunity> bioRepoOpps = new List<Opportunity>();
    List<Opportunity> marketingOpps = new List<Opportunity>();

    for (Opportunity o : updatedOpps) {
        Opportunity originalOpp = oldMap.get(o.Id);

        if (originalOpp == null) continue;

        if (originalOpp.Biorepository__c == true && o.Biorepository__c == false) {
            bioRepoOpps.add(o);
        } else if (originalOpp.Digital_Marketing_Manager__c == true && o.Digital_Marketing_Manager__c == false) {
            marketingOpps.add(o);
        }
    }

    for (Opportunity o : bioRepoOpps) {
        if (o.Lab_Startup_Period__c == null) {
            o.addError(ERR_LAB);
        }
    }
    for (Opportunity o : marketingOpps) {
        if (o.Recruitment_Startup_Period__c == null) {
            o.addError(ERR_REC);
        }
    }
}


    // Unused
    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}
}
