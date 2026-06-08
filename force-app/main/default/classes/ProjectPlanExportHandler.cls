public with sharing class ProjectPlanExportHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'ProjectPlanExportHandler';

    private void runExport() {
        try {
            integrator_da__RealTimeExporter.processExport();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    public void beforeInsert(List<SObject> newRecords) { runExport(); }
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) { runExport(); }
    public void afterDelete(Map<Id, SObject> oldMap) { runExport(); }
    public void afterUndelete(List<SObject> newRecords) { runExport(); }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newRecords) {}
}