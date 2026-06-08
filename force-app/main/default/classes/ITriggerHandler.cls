/**
 * Interface that all trigger handlers must implement
 * Provides methods for all trigger contexts
 */

public interface ITriggerHandler {
    void beforeInsert(List<SObject> newRecords);
    void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap);
    void beforeDelete(Map<Id, SObject> oldRecordsMap);
    void afterInsert(List<SObject> newRecords);
    void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap);
    void afterDelete(Map<Id, SObject> oldRecordsMap);
    void afterUndelete(List<SObject> newRecords);
}