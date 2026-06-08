# Salesforce Trigger Dispatcher Framework

A metadata-driven Apex trigger framework that centralises all trigger logic across multiple SObjects into a single, configurable dispatcher. Handler classes are registered and ordered via Custom Metadata, so new business rules can be added or toggled without touching trigger code.

---

## Table of Contents

- [Architecture](#architecture)
- [How It Works](#how-it-works)
- [Project Structure](#project-structure)
- [Custom Metadata Configuration](#custom-metadata-configuration)
- [Covered SObjects & Handlers](#covered-sobjects--handlers)
- [Adding a New Handler](#adding-a-new-handler)
- [Testing Approach](#testing-approach)
- [Setup & Deployment](#setup--deployment)
- [Design Decisions](#design-decisions)

---

## Architecture

```
AccountTrigger.trigger
        │
        ▼
TriggerDispatcher.dispatch('Account')
        │
        ├── reads TriggerHandlerConfig__mdt  ◄── Custom Metadata (CMDT)
        │       • SObjectName__c = 'Account'
        │       • IsActive__c    = true
        │       • ExecutionOrder__c
        │       • HandlerClass__c
        │
        ├── AccountRepUpdateHandler   (Order 10)  ──► implements ITriggerHandler
        └── AccountAggregateHandler   (Order 30)  ──► implements ITriggerHandler
```

Each trigger contains a single line. All routing, ordering, and activation is controlled through metadata records — no code changes required to add, reorder, or disable a handler.

---

## How It Works

### 1. Trigger — Single Entry Point

Every trigger calls `TriggerDispatcher.dispatch()` with the SObject API name:

```apex
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    TriggerDispatcher.dispatch('Account');
}
```

### 2. TriggerDispatcher — Central Orchestrator

```apex
public class TriggerDispatcher {

    // Loaded once per transaction via static initializer
    private static Map<String, List<TriggerHandlerConfig__mdt>> handlerCache;

    static { loadAllHandlers(); }

    public static void dispatch(String sObjectName) {
        List<TriggerHandlerConfig__mdt> handlers = getHandlers(sObjectName);
        for (TriggerHandlerConfig__mdt config : handlers) {
            executeHandler(config);   // Type.forName() → ITriggerHandler
        }
    }
}
```

- **Static cache** — all active handlers are queried once at class load time and cached for the entire transaction. No per-dispatch SOQL.
- **Dynamic instantiation** — `Type.forName(config.HandlerClass__c)` creates handler instances at runtime; adding a new handler class only requires a CMDT record.
- **`@TestVisible` injection** — `testHandlerCache` lets unit tests inject mock handler configs without hitting the database.

### 3. ITriggerHandler — Contract for All Handlers

```apex
public interface ITriggerHandler {
    void beforeInsert(List<SObject> newRecords);
    void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap);
    void beforeDelete(Map<Id, SObject> oldRecordsMap);
    void afterInsert(List<SObject> newRecords);
    void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap);
    void afterDelete(Map<Id, SObject> oldRecordsMap);
    void afterUndelete(List<SObject> newRecords);
}
```

Every handler implements this interface. Unused contexts are left as empty method bodies — no silent failures.

### 4. Handler Class — Single Responsibility

Each handler class owns one cohesive piece of business logic for one SObject:

```apex
public with sharing class AccountRepUpdateHandler implements ITriggerHandler {

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<Account> changed = filterChanged((List<Account>) newRecords, oldMap);
        if (!changed.isEmpty()) updateRelatedContacts(changed);
    }

    // beforeInsert, beforeUpdate, ... — empty stubs for unused contexts
}
```

---

## Project Structure

```
force-app/
└── main/
    └── default/
        ├── classes/
        │   ├── ITriggerHandler.cls                  ← interface contract
        │   ├── TriggerDispatcher.cls                ← central dispatcher
        │   ├── TriggerDispatcherTest.cls            ← dispatcher unit tests
        │   │
        │   ├── Account*Handler.cls                  ← 2 handlers
        │   ├── Case*Handler.cls                     ← 3 handlers
        │   ├── ClinicalEntry*Handler.cls            ← 6 handlers
        │   ├── Contact*Handler.cls                  ← 4 handlers
        │   ├── Lead*Handler.cls                     ← 2 handlers
        │   ├── Opportunity*Handler.cls              ← 4 handlers
        │   ├── Portal_*Handler.cls                  ← 5 portal-layer handlers
        │   ├── ProjectPlan*Handler.cls              ← 2 handlers
        │   ├── SubjectGroup*Handler.cls             ← 2 handlers
        │   ├── WorkRequest*Handler.cls              ← 3 handlers
        │   └── ...                                  ← remaining domain handlers
        │
        ├── triggers/
        │   ├── AccountTrigger.trigger
        │   ├── CaseTrigger.trigger
        │   ├── ClinicalEntryTrigger.trigger
        │   └── ...                                  ← 19 triggers total
        │
        └── customMetadata/
            └── TriggerHandlerConfig.*.md-meta.xml   ← 38 CMDT records
```

---

## Custom Metadata Configuration

**Object:** `TriggerHandlerConfig__mdt`

| Field | Type | Purpose |
|---|---|---|
| `SObjectName__c` | Text | API name of the SObject this handler targets |
| `HandlerClass__c` | Text | Apex class name (must implement `ITriggerHandler`) |
| `ExecutionOrder__c` | Number | Ascending sort order within the same SObject |
| `IsActive__c` | Checkbox | Toggle a handler on/off without code deployment |

**Sample CMDT record:**

```xml
<CustomMetadata>
    <label>AccountAggregateHandler</label>
    <values>
        <field>SObjectName__c</field>
        <value>Account</value>
    </values>
    <values>
        <field>HandlerClass__c</field>
        <value>AccountAggregateHandler</value>
    </values>
    <values>
        <field>ExecutionOrder__c</field>
        <value>30</value>
    </values>
    <values>
        <field>IsActive__c</field>
        <value>true</value>
    </values>
</CustomMetadata>
```

---

## Covered SObjects & Handlers

| SObject | Handlers | Execution Order |
|---|---|---|
| **Account** | AccountRepUpdateHandler | 10 |
| | AccountAggregateHandler | 30 |
| **Case** | CaseAttributeUpdateHandler | 30 |
| | CasePlanErrorAggregateHandler | 60 |
| | CaseOppCountHandler | 65 |
| **ClinicalEntry__c** | ClinicalEntryValidationHandler | 10 |
| | ClinicalEntryContactHandler | 30 |
| | ClinicalEntryNameHandler | 30 |
| | ClinicalEntryPlanHandler | 40 |
| | ClinicalEntrySurveyHandler | 50 |
| | ClinicalEntryOpsHandler | 60 |
| **Contact** | ContactIdentifierHandler | 20 |
| | ContactMarketingHandler | 30 |
| | ContactTrackingHandler | 30 |
| | ContactSmsAlertHandler | 50 |
| **ContentDocumentLink** | Portal_DocumentVisibilityHandler | 5 |
| | Portal_DocumentEmailHandler | 10 |
| **Criterion__c** | EligibilityCriteriaApprovalHandler | 10 |
| | EligibilityCriteriaAggregatorHandler | 20 |
| **Lead** | LeadMarketingHandler | 20 |
| | LeadQualificationHandler | 40 |
| **Opportunity** | OpportunityApprovalHandler | 10 |
| | OpportunityAttributionHandler | 30 |
| | OpportunityCreateHandler | 50 |
| | OpportunityUpdateHandler | 50 |
| **ProjectPlan__c** | ProjectPlanBusinessHandler | 40 |
| | ProjectPlanExportHandler | 90 |
| **WorkRequest__c** | WorkRequestFieldHandler | 30 |
| | WorkRequestBusinessHandler | 50 |
| | WorkRequestRollupHandler | 70 |
| **BidRecord__c** | SubjectGroupPlanHandler | 25 |
| | SubjectGroupCriteriaOrchestrator | 45 |
| **CollectionRequest__c** | CollectionRequestCommentHandler | 10 |
| **ExternalOrder__c** | ConcurrentTaskHandler | 10 |
| **Notification__c** | Portal_MessageEmailHandler | 10 |
| **ProjectRequest__c** | Portal_ProjectRequestEmailHandler | 10 |
| **SupplyRequest__c** | Portal_SupplyRequestEmailHandler | 10 |
| **AuditEntry__c** | AuditEntryHandler | 10 |

**Total: 17 SObjects · 38 handler classes · 19 triggers**

---

## Adding a New Handler

**Three steps, no existing code changes:**

**Step 1 — Create the handler class**

```apex
public with sharing class MyNewHandler implements ITriggerHandler {

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<MyObject__c> changed = new List<MyObject__c>();
        for (MyObject__c rec : (List<MyObject__c>) newRecords) {
            if (rec.SomeField__c != ((MyObject__c) oldMap.get(rec.Id)).SomeField__c) {
                changed.add(rec);
            }
        }
        if (!changed.isEmpty()) processChanges(changed);
    }

    // Stub unused contexts
    public void beforeInsert(List<SObject> n) {}
    public void beforeUpdate(List<SObject> n, Map<Id, SObject> o) {}
    public void beforeDelete(Map<Id, SObject> o) {}
    public void afterInsert(List<SObject> n) {}
    public void afterDelete(Map<Id, SObject> o) {}
    public void afterUndelete(List<SObject> n) {}
}
```

**Step 2 — Add a CMDT record**

Create `TriggerHandlerConfig.MyNewHandler.md-meta.xml`:

```xml
<CustomMetadata>
    <label>MyNewHandler</label>
    <values><field>SObjectName__c</field><value>MyObject__c</value></values>
    <values><field>HandlerClass__c</field><value>MyNewHandler</value></values>
    <values><field>ExecutionOrder__c</field><value>20</value></values>
    <values><field>IsActive__c</field><value>true</value></values>
</CustomMetadata>
```

**Step 3 — Add a trigger (if not already present)**

```apex
trigger MyObjectTrigger on MyObject__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    TriggerDispatcher.dispatch('MyObject__c');
}
```

Deploy all three files. The dispatcher picks up the new handler automatically.

---

## Testing Approach

The framework uses `@TestVisible` metadata injection so tests run without needing actual CMDT records deployed:

```apex
@IsTest
static void testHandlerIsCalledOnInsert() {
    // Inject a mock handler config — no CMDT records needed
    TriggerDispatcher.testHandlerCache = new Map<String, List<TriggerHandlerConfig__mdt>>{
        'Account' => new List<TriggerHandlerConfig__mdt>{
            new TriggerHandlerConfig__mdt(
                HandlerClass__c    = 'AccountRepUpdateHandler',
                ExecutionOrder__c  = 10,
                IsActive__c        = true,
                SObjectName__c     = 'Account'
            )
        }
    };

    Test.startTest();
    insert new Account(Name = 'Test Account');
    Test.stopTest();

    // Assert expected side effects
}
```

Each handler class has its own dedicated test class (`*HandlerTest.cls`) covering the specific trigger contexts it uses.

---

## Setup & Deployment

### Prerequisites

| Requirement | Version |
|---|---|
| Salesforce CLI (`sf`) | Latest |
| Salesforce API Version | 59.0 |
| Salesforce Edition | Enterprise or above (Custom Metadata) |

### Deploy to a Sandbox

```bash
# Authenticate
sf org login web --alias my-sandbox --instance-url https://test.salesforce.com

# Deploy all metadata
sf project deploy start --source-dir force-app --target-org my-sandbox

# Run all tests after deployment
sf apex run test --target-org my-sandbox --test-level RunLocalTests --wait 10
```

### Deploy to Production

```bash
sf project deploy start \
  --source-dir force-app \
  --target-org production \
  --test-level RunLocalTests
```

### What Gets Deployed

| Metadata Type | Count |
|---|---|
| Apex Classes (handlers + dispatcher + interface) | 65 |
| Apex Triggers | 19 |
| Custom Metadata Records (`TriggerHandlerConfig__mdt`) | 38 |

> **Note:** The Custom Metadata Type object itself (`TriggerHandlerConfig__mdt`) and its field definitions must exist in the target org before deploying. Create them manually or include the object definition in the package.

---

## Design Decisions

| Decision | Rationale |
|---|---|
| **CMDT over Custom Settings** | CMDT records are deployable as metadata; Custom Settings require data scripts. This makes the framework fully source-controlled. |
| **Static cache on class load** | Avoids repeated SOQL on every trigger invocation within the same transaction. One query per transaction regardless of how many handlers exist. |
| **`Type.forName()` instantiation** | Handlers are coupled only via the interface. The dispatcher never imports a handler class — adding or removing handlers requires zero changes to dispatcher code. |
| **`with sharing` on handlers** | Each handler enforces sharing rules independently. The dispatcher itself is `public` (no sharing keyword) to remain callable from any context. |
| **`@TestVisible` injection** | Allows full unit test coverage of the dispatcher's routing and ordering logic without deploying CMDT records to a scratch org. |
| **Execution order as a number** | Gaps between order values (10, 30, 50) allow inserting handlers between existing ones without renumbering. |
| **Single trigger per SObject** | Eliminates trigger ordering non-determinism. All execution order is controlled explicitly through CMDT. |

---

## Author

**S.M. Akbar** — Salesforce Developer  
[LinkedIn](https://www.linkedin.com/in/mohammad-akbar-shaikh-b23165352/) · [GitHub](https://github.com/skakbar0337)

Certifications: Salesforce Associate · Platform Developer I · Data Cloud Consultant · AI Associate
