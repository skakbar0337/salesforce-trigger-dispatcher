trigger HealthProfileTrigger on HealthProfile__c (after insert, before insert, after delete, after update ,
                                                      after undelete, before delete, before update) {

	/*if(Trigger.isInsert && trigger.isAfter){
        HealthProfileTriggerHelper.doAfterInsert(Trigger.New);
    }
    if(Trigger.isUpdate && trigger.isAfter){
        HealthProfileTriggerHelper.doAfterUpdate(Trigger.New, Trigger.oldMap);
    }
    if (Trigger.isUpdate && trigger.isBefore) {
        HealthProfileTriggerHelper.patientOpsTaskCheck(Trigger.new, Trigger.oldMap);
    }
    if(Trigger.isDelete && trigger.isAfter){
        HealthProfileTriggerHelper.doAfterDelete(Trigger.old);
    }
    if(Trigger.isUndelete && trigger.isAfter){
        HealthProfileTriggerHelper.doAfterUndelete(Trigger.New);
    }*/
    TriggerDispatcher.dispatch('HealthProfile__c');

}