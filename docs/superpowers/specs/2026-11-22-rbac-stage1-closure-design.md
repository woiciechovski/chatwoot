# RBAC Stage 1 Closure — Design

**Status:** Approved with user adjustments (2026-11-22)

## Intent

Close the technical review findings in the existing Rails RBAC core so Stage 1 is safe to integrate incrementally. The branch already contains the account-scoped roles, grant catalog, API, audit table, and migration. This work hardens administrative membership changes, makes agent updates atomic, tightens optimistic version input, reconciles denial auditing, and supplies the missing PostgreSQL and compatibility evidence.

## Goals

- Keep at least one usable native administrator on every active account across concurrent membership changes and global user deletion.
- Use one account-scoped lock protocol across supported writers, with deterministic ordering for operations spanning multiple accounts.
- Centralize that protocol in one shared service; callbacks and controller code must not acquire membership locks in another order.
- Roll back both `User` and `AccountUser` changes when an agent update fails, while retaining the API's current error response.
- Accept only documented, in-range integer versions and distinguish malformed versions from stale edits.
- Persist sanitized denial audit events after the rejected mutation has rolled back.
- Test revocation, tenant boundaries, principal compatibility, and migration integrity in PostgreSQL.
- Update `docs/RBAC_CORE_API.md` and add `docs/RBAC_STAGE1_FINAL_REVIEW.md` with evidence and residual risks.

## Non-goals

- Do not start Stage 2, enforce RBAC in business modules, or make any of the seven planned modules assignable.
- Do not add Vue screens, NestJS integration, new product permissions, licensing behavior, or Enterprise functionality.
- Do not modify proprietary files under `enterprise/` or add dependencies.

## Constraints

- Continue in the existing `feat/rbac-core` worktree at `/home/woiciechovski/projetos/chatwoot-rbac-stage0`; the implementation there is uncommitted and must be preserved.
- Keep persistence changes in Rails migrations and application queries in ActiveRecord/Arel.
- Exercise concurrency and migration behavior against an isolated PostgreSQL database; never use a production database.
- Keep all role, membership, and audit lookups tenant-scoped. Do not disclose IDs or data from another account in responses or denial events.
- The lock order is `Account` → `User` → `AccountUser`; acquire multiple account rows in ascending ID order.
- Preserve `rbac_managed`: revocation keeps it true, and domains still marked planned continue using their existing authorization behavior.

## Approaches

1. **Lock the account row in a fixed order (selected).** Every administrative membership transition serializes on its owning `Account`, then locks the affected `User` and `AccountUser`. Global user deletion locks all associated account rows in ascending ID order before the user and membership rows. Model validations remain a backstop for ordinary direct writes. This is explicit, tenant-scoped, and makes the PostgreSQL race test correspond to the production protocol; contention is limited to operations on the same account, except for the necessary multi-account global deletion.
2. **Use PostgreSQL advisory locks per account.** This can avoid row-level contention on `accounts`, but adds a database-specific lock convention that every path must remember. Global user deletion still needs a stable multi-account lock order and coordinated membership handling.
3. **Keep independent record locks and patch callbacks locally.** This minimizes code movement, but does not serialize global user deletion with promotion and leaves lock ordering dependent on callback and controller call order. It cannot establish the requested invariant across all paths.

The user selected approach 1 and requires the lock protocol to live in a shared service. `Rbac::MembershipLockService` will own acquisition and refresh of `Account`, `User`, and `AccountUser` locks. Callers that mutate administrative membership state or create/remove a membership use this service; model callbacks delegate to it as a backstop. The canonical order is `Account` → `User` → `AccountUser`; when more than one account is involved, acquire account locks by ascending primary key. `with_account` supports account-first flows such as AgentBuilder capacity checks and may be extended by one nested membership callback through user then membership. `with_user_memberships` must re-read links after account and user locks are acquired. If a newly observed link belongs to an unlocked account, it must roll back the incomplete attempt and retry the whole acquisition; it must never acquire the newly discovered account lock after the user lock. Nested callbacks may reuse an already-held lock scope; they may extend it only in canonical order and may not add another account or acquire a later user after an AccountUser lock. Supported administrative operations are coordinated by the shared service. Role-row locks may be taken only after these membership locks in assignment flows; role-only edits keep their existing role lock and optimistic version check.

## Design

### Administrator membership lifecycle

Inventory and route every supported native role promotion, demotion, and membership removal through `Rbac::MembershipLockService`: Agents API, Platform API account-user upsert/removal, Super Admin account-user create/update/removal, global `User` destruction, and initial membership creation in `AccountBuilder` and `AgentBuilder`. `AccountBuilder` can link an existing user to a newly created account, so this path must lock the new account and then the user before creating the membership. `AgentBuilder` already locks its account and must follow the same user/membership order. Keep operational updates such as availability and `active_at` out of this lock path. Review callbacks and direct/bulk writes; no supported mutation may bypass the service, validation, or callback protections.

Separate the administrator queries by purpose. For the last-usable-administrator invariant, count persisted native administrator links joined to existing users only on active accounts. For global `User` deletion, block while any persisted native administrator link exists in any account, including suspended accounts; do not use the usable-admin relation for this check. Count links through an account-scoped join so orphaned memberships do not count. In this repository, `Account` has active/suspended states; `AccountUser` has no active flag, and availability values (including offline/busy) are operational rather than access states. `User` has no lockable or disabled flag. Devise Confirmable tracks `confirmed_at` and normally blocks login until confirmation, but account signup intentionally creates its owner membership before confirmation; therefore confirmation gates login but is not treated as membership deletion. The account remains unavailable to that user until the existing confirmation flow succeeds. `AccountDeletionService` anonymizes orphaned users while their account is being torn down; account teardown may remove its own memberships because the account itself is being deleted. `SuperAdmin` is a `User` STI subtype; its installation login is separate, but any account-scoped authority still comes from its `AccountUser` role.

Global user destruction is blocked while the user has any native administrator membership, even if another administrator exists in that account; those links must first be removed through authorized account-scoped operations that preserve the last usable administrator. The service locks all currently linked accounts in ascending ID order, then the user and membership rows, and rechecks memberships under lock. If recheck finds a link in an account outside the acquired set, it rolls back and begins a fresh full lock attempt with the expanded sorted account set. This serializes with a new `AccountBuilder` membership even when its account was not visible when deletion first gathered linked account IDs: membership creation also locks the user before insert, and deletion rechecks all memberships after obtaining that lock. Preserve the existing asynchronous cleanup for non-administrator associations, but do not let asynchronous cleanup decide whether a global deletion was safe.

### Agent update atomicity

Wrap the user name and current account-user attribute update in one database transaction. Keep both writes and their existing callbacks in that transaction so a validation failure rolls them back together and emits each success side effect once. Allow the existing request exception handling to return the same 422 payload.

### Optimistic version input

Accept JSON integer values and ASCII decimal-digit strings for `expected_version`, including zero, up to PostgreSQL's signed `integer` maximum (`2147483647`). Reject floats (including integral-valued JSON floats), booleans, null/missing required values, non-numeric strings, negative values, and values above that maximum as `invalid_version`/422. A valid in-range value that differs from the stored `lock_version` remains `stale_version`/409. Document the accepted numeric string form and test two concurrent edits with the same version.

### Denial auditing

Record one account-scoped denial event for supported attempts to demote/remove the last administrator, delete a user while it retains an administrator membership, or make an unauthorized RBAC administrative change. For a global user deletion denied by administrator memberships in multiple accounts, write one event in each account where that user has an administrator membership, with that account's local `AccountUser` as target; all events share the request ID and contain no other account IDs or cross-account summary. Persist denial events only after the entire protected operation transaction has rolled back; do not write from an inner savepoint or depend on a savepoint surviving rollback of an outer transaction. The operation coordinator must surface the denial outside the transaction before the controller records the event. If writing the event fails, the protected operation remains denied; return/report the audit failure without retrying the mutation or converting it to success. Use the authenticated actor (`AccountUser`, `PlatformApp`, or `SuperAdmin`) for request denials. If a request is authenticated but actor lookup unexpectedly returns nil, do not label it a system event: fail the audit step explicitly while keeping the operation denied. A nil actor may be represented as a system event only for a known non-request system operation. Store only a fixed reason code and safe target type/ID; do not store credentials, tokens, request bodies, or cross-account identifiers. Successful Super Admin recovery remains audited. Any unsupported application path must be named in the API/review documentation.

### RBAC and tenant compatibility

Keep the catalog's seven modules planned and non-assignable. Test role assignment and removal with a reused personal token so each request resolves the current database state; test `Rbac::Authorizer` under a controlled enforced catalog entry without enabling a production module. Cover cross-account role and membership IDs, a user with different roles in two accounts, account-admin isolation, native administrators, agents with no role, RBAC-managed agents after revocation, Platform API, Super Admin, and the existing `custom_role_id` conflict behavior. Do not change Enterprise source files.

### Migration evidence

On an isolated PostgreSQL database, apply the RBAC migration, inspect its tables/indexes/constraints, verify that a cross-account role reference is rejected by the composite foreign key, roll the migration back, and apply it again. Do not make a new constraint unless the migration checks demonstrate a concrete integrity gap.

### Concurrency evidence

Use independent PostgreSQL connections to test lock-set discovery/retry when a user gains a link in an account not included in the initial query; callback reentrancy without lock expansion; an administrator link in a suspended account blocking global deletion while not counting toward active-account usability; and denial-event persistence after a full transaction rollback with missing authenticated actor rejection. Also race admin demotion/removal with another admin mutation and global user deletion. Include a user linked to multiple accounts and a concurrent membership creation through `AccountBuilder`. Assert that global deletion is denied while any native administrator link remains, that one valid administrator remains on each active account after every completed schedule, and that denial audit events are account-local.

## Review and completion evidence

The final review document will list the exact changed files, focused spec and RuboCop totals (including pending examples), the PostgreSQL concurrency schedule and result, migration/rollback evidence, account-isolation guarantees, any validation not run, residual risks, and an approval/rejection recommendation for Stage 1. No Stage 2 work is part of that recommendation.
