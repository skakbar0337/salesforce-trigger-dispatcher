/**
 * @description       : Handler to update Incidence_Check__c.OwnerId when an Account's Territory_SDR__c changes.
 * @author            : Refactored by S.M Akbar
 * @executionOrder    : 10 (Field Update Handler)
 * @notes             :
 *  - Runs WITH SHARING to respect record access.
 *  - Applies CRUD/FLS checks and sanitizes records via Security.stripInaccessible.
 *  - Bulk-safe: processes 200+ Accounts/Contacts/ICs without SOQL/DML in loops.
 *  - Uses partial-success DML and logs failures.
 */
public with sharing class AccountRepUpdateHandler implements ITriggerHandler {

    private static final String CLASS_NAME = 'AccountRepUpdateHandler';
    private static final String PENDING_INC_CHECK_STATUS = 'Submitted';

    // ---------------- ITriggerHandler ----------------

    public void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        try {
            List<Account> newAccounts = toAccounts(newList);
            Map<Id, Account> oldAccounts = toAccountMap(oldMap);

            if (newAccounts.isEmpty() || oldAccounts.isEmpty()) return;

            // FLS check for the field we rely upon from trigger context
            if (!Schema.sObjectType.Account.fields.Territory_SDR__c.isAccessible()) {
                System.debug(LoggingLevel.WARN, 'Territory_SDR__c not accessible for current user. Aborting SDR reassignments.');
                return;
            }

            // Identify Accounts whose SDR changed
            ChangedSdrContext ctx = getAccountsWithChangedSdr(newAccounts, oldAccounts);
            if (ctx.accountIdsWithChangedSdr.isEmpty()) return;

            // CRUD checks for reads (Contact & Incidence_Check__c)
            if (!Schema.sObjectType.Contact.isAccessible() || !Schema.sObjectType.Incidence_Check__c.isAccessible()) {
                System.debug(LoggingLevel.WARN, 'Missing read access to Contact or Incidence_Check__c. Aborting.');
                return;
            }

            // Build Contact -> Account map for impacted Accounts
            Map<Id, Id> contactToAccount = getContactToAccountMap(ctx.accountIdsWithChangedSdr);
            if (contactToAccount.isEmpty()) return;

            // Only consider ICs in "Submitted" owned by the former SDRs
            Set<Id> formerSdrIds = new Set<Id>(ctx.formerSdrIdByAcctId.values());
            if (formerSdrIds.isEmpty()) return;

            List<Incidence_Check__c> candidateICs =
                queryCandidateIncidenceChecks(contactToAccount.keySet(), formerSdrIds);
            if (candidateICs.isEmpty()) return;

            // Prepare reassignment per Account's specific old/new SDR mapping
            List<Incidence_Check__c> toUpdate = new List<Incidence_Check__c>();
            for (Incidence_Check__c ic : candidateICs) {
                Id acctId = contactToAccount.get(ic.Contact__c);
                Id former = ctx.formerSdrIdByAcctId.get(acctId);
                Id newSdr = ctx.newSdrIdByAcctId.get(acctId);

                if (former != null && newSdr != null && ic.OwnerId == former) {
                    ic.OwnerId = newSdr;
                    toUpdate.add(ic);
                }
            }

            if (toUpdate.isEmpty()) return;

            // CRUD/FLS check for write
            if (!Schema.sObjectType.Incidence_Check__c.isUpdateable()
                || !Schema.sObjectType.Incidence_Check__c.fields.OwnerId.isUpdateable()) {
                System.debug(LoggingLevel.WARN, 'No update permission on Incidence_Check__c/OwnerId. Skipping updates.');
                return;
            }

            // Sanitize writable fields before DML
            List<SObject> stripped = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate).getRecords();
            List<Incidence_Check__c> safeUpdates = new List<Incidence_Check__c>();
            for (SObject sob : stripped) safeUpdates.add((Incidence_Check__c) sob);

            performPartialUpdate(safeUpdates);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    // Unused interface hooks
    public void beforeInsert(List<SObject> newList) {}
    public void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    public void afterInsert(List<SObject> newList) {}
    public void beforeDelete(Map<Id, SObject> oldMap) {}
    public void afterDelete(Map<Id, SObject> oldMap) {}
    public void afterUndelete(List<SObject> newList) {}

    // ---------------- Helper Types & Methods ----------------

    private class ChangedSdrContext {
        Set<Id> accountIdsWithChangedSdr = new Set<Id>();
        Map<Id, Id> formerSdrIdByAcctId  = new Map<Id, Id>();
        Map<Id, Id> newSdrIdByAcctId     = new Map<Id, Id>();
    }

    private static ChangedSdrContext getAccountsWithChangedSdr(List<Account> newAccounts,
                                                               Map<Id, Account> oldAccounts) {
        ChangedSdrContext ctx = new ChangedSdrContext();
        for (Account a : newAccounts) {
            Account oldA = oldAccounts.get(a.Id);
            if (oldA == null) continue;

            if (oldA.Territory_SDR__c != a.Territory_SDR__c) {
                ctx.accountIdsWithChangedSdr.add(a.Id);
                ctx.formerSdrIdByAcctId.put(a.Id, oldA.Territory_SDR__c);
                ctx.newSdrIdByAcctId.put(a.Id, a.Territory_SDR__c);
            }
        }
        return ctx;
    }

    private static Map<Id, Id> getContactToAccountMap(Set<Id> accountIds) {
        Map<Id, Id> out = new Map<Id, Id>();
        if (accountIds == null || accountIds.isEmpty()) return out;

        List<Contact> raw = [
            SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds
        ];

        List<SObject> stripped = Security.stripInaccessible(AccessType.READABLE, raw).getRecords();
        for (SObject sob : stripped) {
            Contact c = (Contact) sob;
            out.put(c.Id, c.AccountId);
        }
        return out;
    }

    private static List<Incidence_Check__c> queryCandidateIncidenceChecks(Set<Id> contactIds,
                                                                          Set<Id> formerSdrIds) {
        if (contactIds == null || contactIds.isEmpty() || formerSdrIds == null || formerSdrIds.isEmpty()) {
            return new List<Incidence_Check__c>();
        }

        List<Incidence_Check__c> raw = [
            SELECT Id, Contact__c, OwnerId, Status__c
            FROM Incidence_Check__c
            WHERE Contact__c IN :contactIds
              AND Status__c   = :PENDING_INC_CHECK_STATUS
              AND OwnerId     IN :formerSdrIds
        ];

        return (List<Incidence_Check__c>) Security.stripInaccessible(AccessType.READABLE, raw).getRecords();
    }

    private static void performPartialUpdate(List<Incidence_Check__c> updates) {
        if (updates == null || updates.isEmpty()) return;

        try {
            Database.SaveResult[] results = Database.update(updates, false);
            List<String> errs = new List<String>();

            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error e : results[i].getErrors()) {
                        errs.add('Idx=' + i + ', Status=' + e.getStatusCode() + ', Msg=' + e.getMessage());
                    }
                }
            }
            if (!errs.isEmpty()) {
                System.debug(LoggingLevel.ERROR, 'Partial DML failures: ' + String.join(errs, ' | '));
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, ex.getMessage());
        }
    }

    private static List<Account> toAccounts(List<SObject> records) {
        List<Account> out = new List<Account>();
        if (records == null) return out;
        for (SObject s : records) if (s instanceof Account) out.add((Account) s);
        return out;
    }

    private static Map<Id, Account> toAccountMap(Map<Id, SObject> oldMap) {
        Map<Id, Account> out = new Map<Id, Account>();
        if (oldMap == null) return out;
        for (Id k : oldMap.keySet()) {
            SObject s = oldMap.get(k);
            if (s instanceof Account) out.put(k, (Account) s);
        }
        return out;
    }
}
