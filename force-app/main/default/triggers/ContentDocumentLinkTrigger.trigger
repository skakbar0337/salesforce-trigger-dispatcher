trigger ContentDocumentLinkTrigger on ContentDocumentLink (before insert, after insert) {
    if (Trigger.isAfter) {
        ContentDocumentLinkHelper.doAfterInsert(trigger.New);
    }
    TriggerDispatcher.dispatch('ContentDocumentLink');
}