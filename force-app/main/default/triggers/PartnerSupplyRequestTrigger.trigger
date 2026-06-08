trigger PartnerSupplyRequestTrigger on SupplyRequest__c (before insert, before update) {
    if (Trigger.isBefore) {
        PartnerSupplyRequestTriggerHelper.stampHealthProfileFields(Trigger.new, Trigger.oldMap);
    }
}