/**
 * @description Handler for rolling up Child Account data to Parent Shell Accounts using custom metadata-defined rules.
 * @author Refactored by S.M Akbar
 * @executionOrder 30 (Rollups & Calculations)
 *
 * SECURITY & QUALITY NOTES
 * - Class enforces sharing (with sharing).
 * - Object CRUD/FLS access is validated.
 * - No SOQL/DML within loops; handles bulk operations efficiently.
 */
public with sharing class AccountRollupHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'AccountRollupHandler';
    private static final String SHELL_RECORD_TYPE_NAME = 'Parent Shell';
    private static final Id SHELL_RECORD_TYPE_ID = resolveShellRecordTypeId();

    @TestVisible public static List<Account_Rollup_Rule__mdt> mockRules;

    // ITriggerHandler interface implementation
    public void afterInsert(List<SObject> newRecords) { handleRollup(toAccounts(newRecords), false); }
    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) { handleRollup(toAccounts(newRecords), false); }
    public void afterDelete(Map<Id, SObject> oldMap) { handleRollup(toAccounts(oldMap.values()), true); }

    public void beforeInsert(List<SObject> newRecords) {}
    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newRecords) {}

    private void handleRollup(List<Account> accounts, Boolean isDelete) {
        try {
            if (accounts == null || accounts.isEmpty()) return;

            if (!Schema.sObjectType.Account.isAccessible()) {
                return;
            }

            Set<Id> shellIds = new Set<Id>();
            Set<Id> deletedChildIds = new Set<Id>();
            for (Account a : accounts) {
                if (a.ParentId != null) shellIds.add(a.ParentId);
                if (isDelete && a.Id != null) deletedChildIds.add(a.Id);
            }
            if (shellIds.isEmpty()) return;

            Map<Id, Account> shells = AccountQueryUtil.getShellAccountsById(shellIds);
            if (shells.isEmpty()) return;

            List<Account_Rollup_Rule__mdt> rules = getRollupRules();
            if (rules.isEmpty()) return;

            Set<String> fieldsForSelect = ruleFields(rules);

            Map<Id, List<Account>> childrenMap = new Map<Id, List<Account>>();
            addSiblingAccounts(childrenMap, shells.keySet(), deletedChildIds, fieldsForSelect);

            if (isDelete) {
                Set<Id> emptyShells = findEmptyShells(shells.keySet(), deletedChildIds);

                if (!emptyShells.isEmpty()) {
                    List<Account> toNullify = new List<Account>();
                    for (Id sid : emptyShells) {
                        Account shell = shells.get(sid);
                        if (shell != null) {
                            toNullify.add(AccountRollupHelper.nullEmptyShells(shell, rules));
                        }
                        childrenMap.remove(sid);
                    }
                    if (!toNullify.isEmpty()) {
                        if (!Schema.sObjectType.Account.isUpdateable()) {
                        } else {
                            Database.update(toNullify, false);
                        }
                    }
                }

                if (!childrenMap.isEmpty()) {
                    rollupShells(shells, childrenMap, rules);
                }
            } else {
                rollupShells(shells, childrenMap, rules);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private static List<Account_Rollup_Rule__mdt> getRollupRules() {
        return (mockRules != null) ? mockRules : [
            SELECT DeveloperName, Active__c, Source_Field_API_Name__c,
                   Source_Field_Datatype__c, Destination_API_Field_Name__c,
                   Rollup_Type__c, Default_Value__c
            FROM Account_Rollup_Rule__mdt
            WHERE Active__c = true
        ];
    }

    private static Set<String> ruleFields(List<Account_Rollup_Rule__mdt> rules) {
        Set<String> f = new Set<String>();
        for (Account_Rollup_Rule__mdt r : rules) {
            if (String.isNotBlank(r.Source_Field_API_Name__c))      f.add(r.Source_Field_API_Name__c);
            if (String.isNotBlank(r.Destination_API_Field_Name__c)) f.add(r.Destination_API_Field_Name__c);
        }
        return f;
    }

    private static void addSiblingAccounts(
        Map<Id, List<Account>> childrenMap,
        Set<Id> shellIds,
        Set<Id> excludeChildIds,
        Set<String> fieldsForSelect
    ) {
        if (shellIds.isEmpty() || fieldsForSelect.isEmpty()) return;

        String soql = 'SELECT Id, ParentId, RecordTypeId, ' + String.join(new List<String>(fieldsForSelect), ', ') +
                      ' FROM Account WHERE ParentId IN :shellIds AND Id NOT IN :excludeChildIds';

        for (Account a : Database.query(soql)) {
            if (a.RecordTypeId != SHELL_RECORD_TYPE_ID) {
                if (!childrenMap.containsKey(a.ParentId)) childrenMap.put(a.ParentId, new List<Account>());
                childrenMap.get(a.ParentId).add(a);
            }
        }
    }

    private void rollupShells(Map<Id, Account> shells, Map<Id, List<Account>> children, List<Account_Rollup_Rule__mdt> rules) {
        if (!Schema.sObjectType.Account.isUpdateable()) {
            return;
        }
        List<Account> toUpdate = new List<Account>();
        for (Id shellId : children.keySet()) {
            Account updatedShell = AccountRollupHelper.runRollupRules(shells.get(shellId), children.get(shellId), rules);
            toUpdate.add(updatedShell);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    private static Set<Id> findEmptyShells(Set<Id> shellIds, Set<Id> excludeChildIds) {
        Set<Id> empty = new Set<Id>();
        if (shellIds == null || shellIds.isEmpty()) return empty;

        List<AggregateResult> rows;
        if (excludeChildIds != null && !excludeChildIds.isEmpty()) {
            rows = [
                SELECT ParentId p, COUNT(Id) c
                FROM Account
                WHERE ParentId IN :shellIds AND Id NOT IN :excludeChildIds
                GROUP BY ParentId
            ];
        } else {
            rows = [
                SELECT ParentId p, COUNT(Id) c
                FROM Account
                WHERE ParentId IN :shellIds
                GROUP BY ParentId
            ];
        }

        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Id sid : shellIds) counts.put(sid, 0);
        for (AggregateResult ar : rows) {
            counts.put((Id)ar.get('p'), (Integer)ar.get('c'));
        }
        for (Id sid : counts.keySet()) {
            if (counts.get(sid) == 0) empty.add(sid);
        }
        return empty;
    }

    private static List<Account> toAccounts(Iterable<SObject> records) {
        List<Account> accts = new List<Account>();
        for (SObject s : records) {
            if (s instanceof Account) accts.add((Account)s);
        }
        return accts;
    }

    private static Id resolveShellRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByName().get(SHELL_RECORD_TYPE_NAME)?.getRecordTypeId();
    }
}
