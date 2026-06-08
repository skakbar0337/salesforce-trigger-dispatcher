trigger PartnerDonorRequestTrigger on DonorRequest__c (before insert, before update) {
    if (Trigger.isBefore) {
        PartnerDonorRequestTriggerHelper.stampHealthProfileFields(Trigger.new, Trigger.oldMap);
    }
}