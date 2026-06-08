trigger ClinicalEntryTrigger on ClinicalEntry__c (after insert, before insert, after delete, after update ,
                                                      after undelete, before delete, before update) {

	/*if(Trigger.isInsert && trigger.isAfter){
        ClinicalEntryTriggerHelper.doAfterInsert(Trigger.New);
    }
    if(Trigger.isUpdate && trigger.isAfter){
        ClinicalEntryTriggerHelper.doAfterUpdate(Trigger.New, Trigger.oldMap);
    }
    if (Trigger.isUpdate && trigger.isBefore) {
        ClinicalEntryTriggerHelper.patientOpsTaskCheck(Trigger.new, Trigger.oldMap);
    }
    if(Trigger.isDelete && trigger.isAfter){
        ClinicalEntryTriggerHelper.doAfterDelete(Trigger.old);
    }
    if(Trigger.isUndelete && trigger.isAfter){
        ClinicalEntryTriggerHelper.doAfterUndelete(Trigger.New);
    }*/
    TriggerDispatcher.dispatch('ClinicalEntry__c');

}