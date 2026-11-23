# RBAC Stage 1 Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close Stage 1 RBAC concurrency, atomicity, input-validation, audit, and compatibility gaps in the existing Rails branch without activating any business module.

**Architecture:** Add one shared membership lock service that owns the `Account` → `User` → `AccountUser` lock order, then route native admin transitions and global user deletion through it while retaining model callbacks as a backstop. Make agent updates atomic, parse optimistic versions strictly, persist denial audit events after rollback, and prove the contracts with PostgreSQL specs and migration checks.

**Tech Stack:** Ruby 3.4.4, Rails 7.2, ActiveRecord, PostgreSQL, RSpec, existing Pundit and audit services.

**Spec:** `docs/superpowers/specs/2026-11-22-rbac-stage1-closure-design.md`

## Global Constraints

- “Não iniciar a Etapa 2 nem integrar novos módulos nesta tarefa.” All seven catalog modules remain `planned` and non-assignable.
- Preserve `rbac_managed`: removing a role keeps the marker true; planned domains retain current behavior.
- Centralize administrative membership locks in `Rbac::MembershipLockService`, ordered `Account` → `User` → `AccountUser`; multiple accounts are locked by ascending ID. `with_user_memberships` must re-read links after locking and restart the complete acquisition in a fresh `requires_new` transaction scope if a link points to an unlocked account (a savepoint when nested in a caller transaction). Do not lock membership rows until that recheck is stable. Nested callbacks may reuse, but may not expand, an existing lock scope.
- A global `User` deletion is denied until every native administrator membership has been removed through authorized account-scoped operations.
- Keep two administrator predicates: usable administrators are persisted native admin links joined to users on active accounts; global deletion is blocked by every persisted native admin link, including links on suspended accounts.
- `expected_version` accepts JSON integers and ASCII decimal-digit strings from `0` to `2147483647`; reject floats, booleans, null/missing values, non-numeric strings, negatives, and larger values. A valid stale value returns `409`; invalid format/range returns `422`.
- Continue in `/home/woiciechovski/projetos/chatwoot-rbac-stage0` on the existing `feat/rbac-core` worktree; preserve its pre-existing uncommitted Stage 1 implementation.
- Do not modify `enterprise/`, add Vue/NestJS work, add permissions/features, or add dependencies.
- Run Ruby commands after `eval "$(rbenv init -)"` and use `bundle exec`.
- Use an isolated PostgreSQL test database for concurrency and migration checks. Never run migration rollback tests against production or the shared development database.
- Use Rails/ActiveRecord/Arel for application and migration code; no raw SQL in production paths.
- Preserve existing API error contracts and keep audit records account-scoped and free of credentials, tokens, request bodies, and cross-account identifiers. Persist denials only after the complete protected transaction rolls back; an authenticated request with a missing actor must not be labeled a system event.

## Review Focus

- **Global deletion racing with membership creation or promotion:** either the admin link commits first and deletion is denied, or deletion commits first and the later membership write fails; test both schedules with independent PostgreSQL connections, including `AccountBuilder` linking an existing user to a second account.
- **Admin eligibility and user states:** only active accounts and persisted administrator links joined to existing `User` rows count toward usable administrators; any persisted administrator link, including on suspended accounts, blocks global user deletion. Test both predicates with suspended accounts, orphaned links, unconfirmed signup users, `SuperAdmin` STI users, and offline availability.
- **Agent update partial failure:** when a name write precedes an invalid membership update, the entire operation returns the existing error response and leaves both rows unchanged; test success and last-admin rejection.
- **Optimistic version input and concurrent editing:** test JSON integer/string acceptance, invalid type/range boundaries, and two editors submitting the same valid version; one update succeeds and the other returns stale conflict.
- **Denied audit and tenant boundaries:** test a durable denial event after full outer rollback (not just savepoint rollback), audit-write failure remaining denied, missing actor on authenticated request failing explicitly, one event per affected admin account on global deletion, and no foreign-account IDs/details in responses or events.
- **Lock-set discovery and callback reentrancy:** test that a new account link found after initial discovery releases the incomplete lock set and restarts in a fresh attempt with sorted account IDs; nested callbacks reuse the lock scope and reject expansion without acquiring locks out of order.

---

### Task 1: Centralize membership locks and define usable administrators

**Files:**
- Create: `app/services/rbac/membership_lock_service.rb`
- Modify: `app/models/account.rb`
- Modify: `app/models/account_user.rb`
- Modify: `app/models/user.rb`
- Modify: `app/builders/account_builder.rb`
- Modify: `app/builders/agent_builder.rb`
- Modify: `app/services/rbac/role_management_service.rb`
- Create: `spec/services/rbac/membership_lock_service_spec.rb`
- Modify: `spec/models/account_spec.rb`
- Modify: `spec/models/account_user_spec.rb`
- Modify: `spec/models/user_spec.rb`
- Modify: `spec/builders/account_builder_spec.rb`
- Modify: `spec/builders/agent_builder_spec.rb`

**Interfaces:**
- `Rbac::MembershipLockService.with_account(account_id:) { |account| ... }` owns account-first flows such as AgentBuilder capacity checks. A nested membership callback may extend this account-only scope by locking one user and then its membership; it may not add another account or add a later user after a membership lock.
- `Rbac::MembershipLockService.with_membership(account_id:, user_id:, membership_id: nil) { |account, user, membership| ... }` starts/joins a transaction, locks the account, user, and persisted membership in that order, and yields fresh records. A missing membership is valid only for a create path.
- `Rbac::MembershipLockService.with_user_memberships(user_id:) { |accounts, user, memberships| ... }` discovers linked accounts, locks them in ascending ID order, then the user, and re-queries before locking membership rows ordered by `[account_id, id]`. If refreshed links contain an account outside the lock set, it rolls back the incomplete `requires_new` transaction scope and retries the whole acquisition; nested callers use a savepoint to release those attempt's locks, then retain successful locks through the outer transaction. It does not lock the new account or its membership after the user.
- Nested calls may reuse a lock scope only when the requested account/user/membership is already covered. If a callback or caller needs to expand the scope, fail before acquiring anything else and route the operation through the coordinator with a complete lock set.
- `Account#usable_administrators` returns an account-scoped relation of persisted native administrator links joined to existing users, and returns none for suspended accounts. `AccountUser` availability and user confirmation do not change membership eligibility.
- The global deletion predicate separately queries all persisted native administrator links for the user, without filtering suspended accounts. Orphaned links are excluded because they cannot be joined to a persisted user.

- [x] **Step 1: Add failing service and model specs.** Cover the two lock-service interfaces, account ID ordering for multi-account users, a membership discovered in a previously unlocked account forcing a fresh full retry, reentrant callbacks reusing the current lock scope, and scope expansion being rejected without new locks. Verify active-account usable admin counts versus all-account global-delete blocking, plus orphaned links, suspended accounts, unconfirmed owner membership, `SuperAdmin` STI membership, and offline/busy administrators.
- [x] **Step 2: Run the new specs to confirm the service and eligibility behavior are absent or incorrect.** Run `eval "$(rbenv init -)" && bundle exec rspec spec/services/rbac/membership_lock_service_spec.rb spec/models/account_user_spec.rb spec/models/user_spec.rb` against isolated PostgreSQL.
- [x] **Step 3: Implement `Rbac::MembershipLockService` and separate usable-admin/global-delete relations.** Retry the entire account→user→membership acquisition in a fresh `requires_new` transaction scope when refreshed membership links reveal an unlocked account.
- [x] **Step 4: Route `AccountUser` security-state callbacks and role assignment/removal service paths through the shared coordinator.** Restrict callbacks to create/destroy and role/RBAC/custom-role state changes; do not lock routine availability or `active_at` updates. Reentrant callbacks must reuse covered scopes and must reject lock-set expansion before further acquisition.
- [x] **Step 5: Route `AccountBuilder` and `AgentBuilder` membership creation through the same order.** Preserve the existing new-account signup flow and its confirmation behavior.
- [x] **Step 6: Run the focused specs and inspect the lock acquisition order in the final diff.** Expect passing model/service/builder examples and no direct AccountUser lock preceding an Account lock.
- [x] **Step 7: Review the focused diff and record the lock-order evidence.** Leave changes uncommitted unless the user asks for a commit.

### Task 2: Protect admin mutations and global user deletion

**Files:**
- Modify: `app/controllers/api/v1/accounts/agents_controller.rb`
- Modify: `app/controllers/platform/api/v1/account_users_controller.rb`
- Modify: `app/controllers/platform/api/v1/users_controller.rb`
- Modify: `app/controllers/super_admin/account_users_controller.rb`
- Modify: `app/controllers/super_admin/users_controller.rb`
- Modify: `app/jobs/delete_object_job.rb` only if actor/request context must cross the existing async user-delete boundary
- Modify: `app/models/user.rb`
- Modify: `app/services/rbac/role_management_service.rb`
- Modify: `spec/models/account_user_concurrency_spec.rb`
- Modify: `spec/controllers/api/v1/accounts/agents_controller_spec.rb`
- Modify: `spec/controllers/platform/api/v1/account_users_controller_spec.rb`
- Modify: `spec/controllers/platform/api/v1/users_controller_spec.rb`
- Modify: `spec/controllers/super_admin/account_users_controller_spec.rb`
- Modify: `spec/controllers/super_admin/users_controller_spec.rb`
- Modify: `spec/builders/account_builder_spec.rb`

**Interfaces:** Use Task 1's `Rbac::MembershipLockService`; native account role promotion/demotion/removal, membership creation/removal, and global deletion must not introduce local lock sequences. Global deletion rejects any remaining administrator membership and requires prior authorized account-scoped removal.

- [x] **Step 1: Add failing PostgreSQL concurrency specs.** Race two last-admin removals/demotions; race promotion against global deletion; race removal against deletion for a user linked to multiple accounts; race `AccountBuilder` linking that user into a new account; and deterministically insert a new account link between initial account discovery and the locked re-query. Assert the service restarts the full acquisition in sorted order, global deletion is denied while any admin membership exists (including suspended accounts), and every active account retains its usable administrator after each committed schedule.
- [x] **Step 2: Add failing request/model specs for all supported paths.** Cover Agents API, Platform API upsert/removal, Super Admin create/removal, Platform global user deletion, Super Admin global user deletion, and model-level direct `User#destroy` protection. Verify successful admin recovery and that deletion succeeds only after admin links are explicitly removed. The existing Super Admin AccountUser routes expose create/show/destroy only; there is no supported update route to migrate.
- [x] **Step 3: Run the focused lifecycle specs before implementation.** Run the focused lifecycle specs against isolated PostgreSQL; the orphan-parent teardown regression failed before its callback fix.
- [x] **Step 4: Route each controller and global delete path through Task 1's coordinator.** Recheck all global administrator memberships while locks are held; retain asynchronous cleanup for unrelated user associations; preserve actor/request context where a later denial audit is required. Audit callback reentrancy and ensure no controller, builder, or service adds account/user/membership locks outside the coordinator.
- [x] **Step 5: Audit every core path that can bypass callbacks or validations.** Search `update_all`, `delete_all`, `delete`, `update_columns`, dependent async associations, and all AccountUser role writes; remove or constrain supported bypasses and document teardown-only behavior.
- [x] **Step 6: Rerun focused lifecycle/concurrency specs.** Expect both operations to serialize safely, unauthorized/last-admin attempts to retain their existing error responses, and no successful global delete while any administrator link remains.
- [x] **Step 7: Review the focused diff and record the lifecycle/concurrency evidence.** Leave changes uncommitted unless the user asks for a commit.

### Task 3: Make agent updates atomic

**Files:**
- Modify: `app/controllers/api/v1/accounts/agents_controller.rb`
- Modify: `spec/controllers/api/v1/accounts/agents_controller_spec.rb`

**Interfaces:** Keep the existing API response/error handler. When a request changes the native role, acquire Task 1's membership locks before writing the `User`; commit the name and AccountUser changes as one transaction.

- [x] **Step 1: Add request specs for successful name+role updates, last-admin demotion after a name change, and a forced AccountUser validation failure after the User write.** Assert full rollback on failure and exact 422 response behavior.
- [x] **Step 2: Run the three focused examples and confirm the name currently persists when the membership write fails.** Run the Agents API spec against isolated PostgreSQL; the new rollback examples initially showed the name persisted because the coordinator joined the surrounding test transaction.
- [x] **Step 3: Wrap both writes in one transaction and acquire account/user/membership locks before either write whenever the native role changes.** Keep AccountUser callbacks and success effects inside the same transaction so they run once after commit.
- [x] **Step 4: Rerun the focused Agents API specs.** Expect success to update both rows and every membership failure to leave both rows unchanged with the existing 422 body.
- [x] **Step 5: Review the focused diff and record the atomicity evidence.** Leave changes uncommitted unless the user asks for a commit.

### Task 4: Validate `expected_version` strictly and prove concurrent edits

**Files:**
- Modify: `app/services/rbac/role_management_service.rb`
- Modify: `app/controllers/api/v1/accounts/rbac/base_controller.rb`
- Modify: `spec/services/rbac/role_management_service_spec.rb`
- Modify: `spec/requests/api/v1/accounts/rbac_spec.rb`
- Modify: `docs/RBAC_CORE_API.md`

**Interfaces:** Add a private parser in `Rbac::RoleManagementService` that returns an integer in `0..2147483647`, accepting Ruby `Integer` and ASCII decimal-digit `String` only. Keep `InvalidVersionError` separate from `StaleVersionError` and preserve `422 invalid_version` versus `409 stale_version`.

- [x] **Step 1: Add failing service/request cases for integer `1`, string `"1"`, zero, `1.9`, `1.0` as a float, `true`, `nil`, non-numeric text, negative values, and values above `2147483647`.** Assert accepted strings are documented and invalid values never mutate the role or grants.
- [x] **Step 2: Add a two-connection PostgreSQL test where both editors submit the same current role version.** Assert one succeeds and the second receives `StaleVersionError`/409 without overwriting the winner.
- [x] **Step 3: Run the focused service/request specs and confirm the loose `Integer(...)` coercion fails the decimal tests.** Run focused specs against isolated PostgreSQL; float `1.0` initially became a stale conflict instead of an invalid version.
- [x] **Step 4: Implement strict parsing and retain the role row lock/optimistic version transaction.**
- [x] **Step 5: Document the integer and numeric-string contract and rerun the focused specs.** Expect invalid input to return 422 and a valid stale value to return 409.
- [x] **Step 6: Review the focused diff and record the version-validation evidence.** Leave changes uncommitted unless the user asks for a commit.

### Task 5: Persist denial audit events safely and per account

**Files:**
- Modify: `app/services/rbac/audit_events/recorder.rb`
- Modify: `app/services/rbac/role_management_service.rb`
- Modify: `app/controllers/api/v1/accounts/base_controller.rb`
- Modify: `app/controllers/api/v1/accounts/agents_controller.rb`
- Modify: `app/controllers/api/v1/accounts/rbac/base_controller.rb`
- Modify: `app/controllers/platform/api/v1/account_users_controller.rb`
- Modify: `app/controllers/platform/api/v1/users_controller.rb`
- Modify: `app/controllers/super_admin/account_users_controller.rb`
- Modify: `app/controllers/super_admin/users_controller.rb`
- Modify: `spec/services/rbac/role_management_service_spec.rb`
- Modify: `spec/controllers/api/v1/accounts/agents_controller_spec.rb`
- Modify: `spec/controllers/platform/api/v1/account_users_controller_spec.rb`
- Modify: `spec/controllers/platform/api/v1/users_controller_spec.rb`
- Modify: `spec/controllers/super_admin/account_users_controller_spec.rb`
- Modify: `spec/controllers/super_admin/users_controller_spec.rb`
- Modify: `spec/requests/api/v1/accounts/rbac_spec.rb`

**Interfaces:** `Rbac::AuditEvents::Recorder.record_denied!` records a fixed reason code, action, local target type/ID, authenticated actor type/ID, and request ID. It may represent a nil actor as a system event only when the caller identifies a known non-request system operation; an authenticated request with missing actor context raises an explicit audit-context failure. Global user deletion with administrator links in multiple accounts records one local event per admin membership/account, never a cross-account summary.

- [x] **Step 1: Add failing request specs for denial audits from Agents API, Platform API, Super Admin, and RBAC authorization, including a global user with admin links in two accounts.** Assert audit events persist only after the complete outer operation rolls back (not merely after a savepoint), are scoped to each local account, and contain no foreign IDs or sensitive input.
- [x] **Step 2: Add failure-injection specs where audit persistence raises.** Assert the protected operation remains denied and no User/AccountUser/role mutation commits.
- [x] **Step 2a: Add PostgreSQL coverage for an authenticated request whose actor lookup returns nil.** Assert it fails explicitly as an audit-context error and never creates a `system` event or allows the denied operation.
- [x] **Step 3: Run the focused audit/controller specs.** Run `eval "$(rbenv init -)" && bundle exec rspec spec/services/rbac/role_management_service_spec.rb spec/controllers/api/v1/accounts/agents_controller_spec.rb spec/controllers/platform/api/v1/account_users_controller_spec.rb spec/controllers/platform/api/v1/users_controller_spec.rb spec/controllers/super_admin/account_users_controller_spec.rb spec/controllers/super_admin/users_controller_spec.rb spec/requests/api/v1/accounts/rbac_spec.rb` against isolated PostgreSQL.
- [x] **Step 4: Write denial events only after the complete protected transaction has rolled back.** Keep the denial exception outside the transaction coordinator and record in a separate transaction; do not write from an inner rescue/savepoint. Preserve denial when recorder fails, reject missing actor context on authenticated requests, and use per-account targets for global deletion.
- [x] **Step 5: Rerun the focused audit specs.** Expect denial status to remain non-success even if the audit writer fails, and every persisted event to expose only its own account's details.
- [x] **Step 6: Review the focused diff and record the denial-audit evidence.** Leave changes uncommitted unless the user asks for a commit.

### Task 6: Complete tenant, revocation, and compatibility coverage

**Files:**
- Modify: `spec/requests/api/v1/accounts/rbac_spec.rb`
- Modify: `spec/services/rbac/authorizer_spec.rb`
- Modify: `spec/models/account_user_spec.rb`
- Modify: existing Platform API and Super Admin account-user specs as needed
- Do not modify: `enterprise/`

**Interfaces:** Use the existing `/rbac/me/capabilities` API and `Rbac::Authorizer`; keep the catalog planned in production. Test a controlled enforced catalog entry only inside specs.

- [x] **Step 1: Add account-isolation specs.** Cover a user with different account roles, an administrator in A denied from RBAC administration in B, foreign account role and membership IDs, and no cross-account audit disclosure.
- [x] **Step 2: Add same-personal-token revocation coverage.** Assign a role and controlled valid grant, evaluate authorization, remove the role/grant, make a fresh request with the same token, and assert the capability state and `Rbac::Authorizer` reflect current database state while `rbac_managed` stays true.
- [x] **Step 3: Cover native administrator, agent without role, RBAC-managed agent, removed role, PlatformApp, SuperAdmin, and `custom_role_id` compatibility using only shared/core code.** Do not activate a production module or edit Enterprise source/specs.
- [x] **Step 4: Run the RBAC, account-user, Platform API, Super Admin, and relevant existing compatibility specs.** Record skipped Enterprise-only examples as pending/unavailable rather than treating them as passes.
- [x] **Step 5: Review the focused diff and record tenant/revocation compatibility evidence.** Leave changes uncommitted unless the user asks for a commit.

### Task 7: Validate the migration, update API docs, and publish the final review

**Files:**
- Modify: `docs/RBAC_CORE_API.md`
- Create: `docs/RBAC_STAGE1_FINAL_REVIEW.md`
- Inspect: `db/migrate/20261122141506_create_rbac_core.rb` and `db/schema.rb`
- Run: focused RSpec suite, changed-file RuboCop, and `git diff --check`

- [x] **Step 1: On a disposable PostgreSQL database, apply `CreateRbacCore` from the pre-RBAC schema.** Verify tables, indexes, the composite tenant foreign key, and account/role/user integrity; assert that a cross-account role assignment is rejected by the database.
- [x] **Step 2: Roll back only migration version `20261122141506`, confirm the RBAC tables/columns/constraints are removed, then apply the same version again and repeat the integrity assertions.** Do not use the shared development or production database.
- [x] **Step 3: Update `docs/RBAC_CORE_API.md`.** Document strict `expected_version` types/range, global user deletion requiring prior authorized admin-link removal, audit denial fields/fanout, usable-administrator definition, and any unsupported administrative event path.
- [x] **Step 4: Run the complete focused suite and RuboCop on every changed Ruby file.** Record exact examples/passes/failures/pending and offenses; run `git diff --check` and confirm no files under `enterprise/`, Vue, module policies, or licensing changed.
- [x] **Step 5: Create `docs/RBAC_STAGE1_FINAL_REVIEW.md` with changed files, concurrency schedules/results, account isolation, migration/rollback evidence, validation gaps, residual risks, and a Stage 1 approve/reject recommendation.** Do not propose or start Stage 2.
- [x] **Step 6: Review the complete diff and leave the branch on `feat/rbac-core` with the implementation and final review available for inspection.** Do not commit unless requested.

---

## Plan Self-Review

- **Spec coverage:** P1 lock protocol/global deletion/lifecycle paths are Tasks 1–2; P2 atomic update is Task 3; expected versions are Task 4; denial audit is Task 5; revocation, isolation, and compatibility are Task 6; migration/API/final review are Task 7.
- **Step scan:** Each task starts with a failing regression, implements one behavior group, reruns the named specs, and records the task result. No planned step depends on activating a business module.
- **Type consistency:** `with_account` yields an `Account`; `with_membership` yields `(Account, User, AccountUser | nil)`; `with_user_memberships` yields `(Array<Account>, User, Array<AccountUser>)`; nested calls may extend only account→user→membership in order.
- **Review Focus:** Every listed input/failure class has an owning test step in Tasks 1–6.
- **Proportion:** The plan separates the shared P1 lock foundation from endpoint migrations, then treats atomicity, version parsing, auditing, compatibility, and final validation as reviewable deliverables.
