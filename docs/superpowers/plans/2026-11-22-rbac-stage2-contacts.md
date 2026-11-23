# RBAC Contacts Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Keep the existing worktree and branch `feat/rbac-core`; do not revert or overwrite the Etapa 1 work.

**Goal:** Enforce explicit account-scoped RBAC permissions across authenticated Contacts operations, their auxiliary paths, downloads, and asynchronous work.

**Architecture:** Reuse `ContactPolicy` and `Rbac::Authorizer` as the only authorization source for user grants. User-initiated jobs carry an account/user identity and revalidate it at execution and bounded batch boundaries; trusted system operations carry an internal allowlisted origin and fail closed when origin is absent or unrecognized. Keep Contacts catalog entries planned and non-assignable until the complete integration has passed PostgreSQL-backed validation and the review has been presented.

**Tech Stack:** Rails, Pundit, Active Job, Active Storage streaming, Vue 3, RSpec, PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-11-22-rbac-contacts-design.md`

## Global Constraints

- Preserve native administrator behavior, unmanaged-agent behavior, `rbac_managed` semantics, account isolation, Community compatibility, and the independent NestJS surface.
- Do not edit `enterprise/`, add an RBAC admin UI, or start the other six module integrations.
- Use existing Pundit policies and `Rbac::Authorizer`; do not create a second authorization engine.
- Do not treat missing `AccountUser` as authorization; system-origin operations require both an allowlisted origin and trusted principal identity scoped to the contact/account. Neither may come from request parameters.
- Revalidate asynchronous authorization before execution and between batches of at most 100 records. A revocation committed during a batch permits only that in-flight batch to finish; subsequent batches stop.
- Keep all Contacts permission catalog entries `planned` and non-assignable through deliveries 1–3. Change Contacts to `enforced` only after tests pass and the user reviews the evidence.
- Keep the other six catalog domains `planned`.

## Review Focus

1. A managed agent with no role/grant or only a different Contacts permission must not reach a protected endpoint or mutate data. Test in Tasks 1–3.
2. Grant revocation after enqueue or during multi-record work must stop later batches; no `AccountUser` or an untrusted origin must fail closed. Test in Task 2.
3. Contact history, attachments, and merges must not reveal or mutate conversations outside `Conversations::PermissionFilterService`. Test in Tasks 2–3.
4. Mutation grants must not reveal existing contact fields through response templates when `contacts.read` is absent. Test in Tasks 1–3.
5. A `contacts.update` grant must not administer Companies or other modules through `company_id`, company association callbacks, or nested company endpoints. Company creates triggered by contact callbacks require `CompanyPolicy#create?`. Test in Task 2.
6. New Contacts responses must not issue permanent Active Storage URLs for avatars/attachments; old links already issued remain a documented residual. Test in Task 3.

---

### Task 1: CRUD policy and staged catalog wiring

**Files:**
- Modify: `app/policies/contact_policy.rb`
- Modify: `app/services/rbac/catalog.rb`
- Modify: `app/controllers/api/v1/accounts/rbac/capabilities_controller.rb`
- Test: `spec/policies/contact_policy_spec.rb`
- Test: `spec/requests/api/v1/accounts/contacts_rbac_spec.rb`
- Test: `spec/requests/api/v1/accounts/rbac_spec.rb`

**Interfaces:**
- `ContactPolicy` maps read/create/update/delete and the proposed import/export actions to the existing `Rbac::Authorizer` for managed agents; unmanaged agents and native administrators retain their prior policy behavior.
- Catalog adds definitions for `contacts.import` and `contacts.export`, but every Contacts entry remains `status: 'planned'`, `assignable: false` until Task 4.
- `/rbac/me/capabilities` returns effective Contacts capabilities using the same policy decisions that govern the Rails endpoints.

- [x] **Step 1: Add a failing request spec for managed-user CRUD grants.** Cover no grant, each CRUD grant alone, a different grant not compensating, native administrator, legacy agent, unchanged database state after denial, and no full contact serialization when an update/create grant is present without read. Use a test catalog override to mark Contacts enforced while production entries remain planned.
- [x] **Step 2: Run the focused request/policy specs and confirm failures are authorization failures.**

Run: `eval "$(rbenv init -)"; bundle exec rspec spec/policies/contact_policy_spec.rb spec/requests/api/v1/accounts/contacts_rbac_spec.rb`

Expected: new managed-agent cases fail because Contact endpoints still use permissive legacy policy behavior.

- [x] **Step 3: Map ContactPolicy actions to existing Authorizer permissions and add the planned import/export catalog entries.** Do not change Contacts status or assignability.
- [x] **Step 4: Add failing-then-passing assertions for capability output and verify the focused specs.**

Run: `eval "$(rbenv init -)"; bundle exec rspec spec/policies/contact_policy_spec.rb spec/requests/api/v1/accounts/contacts_rbac_spec.rb spec/requests/api/v1/accounts/rbac_spec.rb`

Expected: PASS; all six Contacts catalog entries remain planned and non-assignable.

- [x] **Step 5: Report Delivery 1 results to the user without activating Contacts.**

### Task 2: Auxiliary operations and asynchronous authorization

**Files:**
- Modify: `app/controllers/api/v1/accounts/contacts_controller.rb`
- Modify: `app/controllers/api/v1/accounts/contacts/base_controller.rb`
- Modify: `app/controllers/api/v1/accounts/contacts/notes_controller.rb`
- Modify: `app/controllers/api/v1/accounts/contacts/labels_controller.rb`
- Modify: `app/controllers/api/v1/accounts/contacts/contact_inboxes_controller.rb`
- Modify: `app/controllers/api/v1/accounts/contacts/conversations_controller.rb`
- Modify: `app/controllers/api/v1/accounts/contacts/attachments_controller.rb`
- Modify: `app/controllers/api/v1/accounts/search_controller.rb` and `app/services/search_service.rb`
- Modify: `app/controllers/api/v1/accounts/companies/contacts_controller.rb`
- Modify: `app/controllers/api/v1/accounts/actions/contact_merges_controller.rb`
- Modify: `app/controllers/api/v1/accounts/bulk_actions_controller.rb`
- Modify: `app/policies/data_import_policy.rb` and data-import controllers/jobs/services as required
- Modify: `app/jobs/contacts/bulk_action_job.rb`, `app/services/contacts/bulk_action_service.rb`, and batch mutation services
- Modify: `app/jobs/data_import_job.rb` and contact import page jobs as required
- Modify: `app/jobs/avatar/avatar_from_gravatar_job.rb`, `app/jobs/avatar/avatar_from_url_job.rb`, `app/models/concerns/avatarable.rb`
- Modify: `app/services/contacts/company_association_service.rb` and `app/models/concerns/contact_company_association.rb`
- Test: corresponding controller, request, policy, action, and job specs under `spec/`

**Interfaces:**
- Reuse `ContactPolicy` action decisions for nested controllers, search, merge, bulk actions, and import lifecycle.
- User jobs carry `account_id` and `user_id`; integration/CSV import records retain the initiating user. Internal jobs carry an allowlisted origin plus a trusted principal identity set only at verified call sites.
- Bulk and import/export worker code checks authorization before work and at each batch boundary of at most 100 records. Revocation stops future batches; already committed batches remain and the operation records a failure result.
- Contact merge requires read+update+delete for both contacts and full visibility of all affected conversations.
- Company association changes also pass the existing `CompanyPolicy`; an email/company callback that can create a Company must be pre-authorized through `CompanyPolicy#create?`. Contacts grants do not grant Company CRUD.

- [x] **Step 1: Add failing request/job specs for notes, labels, contact-inbox links, custom attributes, avatar deletion, company association, history, attachments, merge, global search, and bulk labels/deletes.** Assert no unauthorized mutation, no unapproved Company creation, no full-contact response without read, and existing conversation filtering.
- [x] **Step 2: Run the focused specs and confirm each failure reproduces an uncovered path.**

Run: `eval "$(rbenv init -)"; bundle exec rspec spec/requests/api/v1/accounts/contacts_rbac_spec.rb spec/controllers/api/v1/accounts/contacts/notes_controller_spec.rb spec/controllers/api/v1/accounts/contacts/labels_controller_spec.rb spec/controllers/api/v1/accounts/contacts/contact_inboxes_controller_spec.rb spec/controllers/api/v1/accounts/contacts/conversations_controller_spec.rb spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb spec/controllers/api/v1/accounts/search_controller_spec.rb spec/controllers/api/v1/accounts/actions/contact_merges_controller_spec.rb spec/controllers/api/v1/accounts/bulk_actions_controller_spec.rb spec/controllers/api/v1/accounts/companies/contacts_controller_spec.rb`

Expected: managed-agent denial/allowance cases fail on uncovered auxiliary paths; legacy and administrator expectations stay green.

- [x] **Step 3: Add failing job tests for actor propagation, trusted system origin and principal identity, role/grant revocation before execution, revocation between batches, contacts-only versus mixed integration imports, and avatar callback propagation.** Missing/unknown origins, mismatched account/contact identities, and caller-supplied origin values must not mutate contacts; only code-controlled allowlisted origins with verified principals may use a system path.
- [x] **Step 4: Run the focused jobs/import specs and confirm the revocation boundary.**

Run: `eval "$(rbenv init -)"; bundle exec rspec spec/jobs/contacts/bulk_action_job_spec.rb spec/jobs/data_import_job_spec.rb spec/jobs/data_imports/freshdesk/import_jobs_spec.rb spec/jobs/data_imports/intercom/import_jobs_spec.rb spec/jobs/avatar/avatar_from_gravatar_job_spec.rb spec/jobs/avatar/avatar_from_url_job_spec.rb spec/services/contacts/bulk_action_service_spec.rb spec/services/contacts/bulk_delete_service_spec.rb spec/services/contacts/bulk_assign_labels_service_spec.rb spec/services/contacts/bulk_remove_labels_service_spec.rb`

Expected: new specs fail when a missing actor currently performs work or when jobs fail to revalidate at a batch boundary.

- [x] **Step 5: Implement the auxiliary policy gates and job checks, preserving legacy user behavior and existing conversation/company policies.** Revalidate before any per-batch write; ensure import/export output is not published after revocation.
- [x] **Step 6: Re-run Task 2 specs and changed Ruby RuboCop.**

Run: `eval "$(rbenv init -)"; bundle exec rspec spec/requests/api/v1/accounts/contacts_rbac_spec.rb spec/controllers/api/v1/accounts/contacts/notes_controller_spec.rb spec/controllers/api/v1/accounts/contacts/labels_controller_spec.rb spec/controllers/api/v1/accounts/contacts/contact_inboxes_controller_spec.rb spec/controllers/api/v1/accounts/contacts/conversations_controller_spec.rb spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb spec/controllers/api/v1/accounts/search_controller_spec.rb spec/controllers/api/v1/accounts/actions/contact_merges_controller_spec.rb spec/controllers/api/v1/accounts/bulk_actions_controller_spec.rb spec/controllers/api/v1/accounts/companies/contacts_controller_spec.rb spec/jobs/contacts/bulk_action_job_spec.rb spec/jobs/data_import_job_spec.rb spec/jobs/data_imports/freshdesk/import_jobs_spec.rb spec/jobs/data_imports/intercom/import_jobs_spec.rb spec/jobs/avatar/avatar_from_gravatar_job_spec.rb spec/jobs/avatar/avatar_from_url_job_spec.rb spec/services/contacts/bulk_action_service_spec.rb spec/services/contacts/bulk_delete_service_spec.rb spec/services/contacts/bulk_assign_labels_service_spec.rb spec/services/contacts/bulk_remove_labels_service_spec.rb`

Expected: PASS, with no cross-account data changes and no work beyond the first in-flight batch after revocation.

- [x] **Step 7: Report Delivery 2 results to the user; Contacts remains planned.**

### Task 3: Authenticated downloads and Contacts UI capabilities

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/api/v1/accounts/contacts/avatar_downloads_controller.rb`
- Modify: `app/controllers/api/v1/accounts/contacts/attachments_controller.rb` for authenticated show/download
- Modify: contact and attachment Jbuilder templates under `app/views/api/v1/accounts/contacts/` and shared contact partials where appropriate
- Modify: `app/jobs/account/contacts_export_job.rb`
- Modify: `app/javascript/dashboard/api/contacts.js` and the Contacts UI avatar/media components
- Modify: existing Contacts controls using `dashboard/components/policy.vue` and `dashboard/composables/usePolicy.js`
- Test: `spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb`, `spec/requests/api/v1/accounts/contacts_rbac_spec.rb`, `spec/jobs/account/contacts_export_job_spec.rb`, and Vue specs at `app/javascript/dashboard/composables/spec/usePolicy.spec.js` and `app/javascript/dashboard/api/specs/contacts.spec.js`

**Interfaces:**
- Contact endpoint payloads expose authenticated application routes for avatars, contact-aggregated attachments, and exports. Attachment route authorizes `contacts.read` and rechecks conversation visibility before streaming.
- Contact UI retrieves protected media through Axios and revokes local object URLs on component/contact changes. Conversation and public/widget media paths retain their current policies and behavior.
- The existing RBAC capabilities endpoint supplies effective Contacts capabilities. UI gates are usability checks only; Rails remains authoritative. Merge requires all read/update/delete capabilities, not the existing any-of behavior.

- [x] **Step 1: Add failing request specs showing that a revoked/non-granted user cannot retrieve an avatar, attachment, or export, while an authorized user can retrieve only account-scoped and conversation-visible media.** Assert new Contact endpoint payloads do not disclose Active Storage bearer URLs and write responses without read do not serialize existing contact fields.
- [x] **Step 2: Add failing Vue specs for Contacts read/create/update/delete/import/export visibility and all-of merge gating, plus object URL cleanup.**
- [x] **Step 3: Implement authenticated streaming routes and replace export email links with the authenticated download URL.** Do not change global Active Storage routes.
- [x] **Step 4: Implement authenticated Axios media fetching and existing policy-component gates without adding administrative UI or changing other module policy behavior.**
- [x] **Step 5: Run focused request/Vue specs, Ruby RuboCop, and ESLint on the changed paths.**

Run: `eval "$(rbenv init -)"; bundle exec rspec spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb spec/requests/api/v1/accounts/contacts_rbac_spec.rb spec/jobs/account/contacts_export_job_spec.rb`

Run: `pnpm test app/javascript/dashboard/composables/spec/usePolicy.spec.js app/javascript/dashboard/api/specs/contacts.spec.js`

Run: `eval "$(rbenv init -)"; bundle exec rubocop app/policies/contact_policy.rb app/services/rbac/catalog.rb app/controllers/api/v1/accounts/rbac/capabilities_controller.rb app/controllers/api/v1/accounts/contacts_controller.rb app/controllers/api/v1/accounts/contacts/base_controller.rb app/controllers/api/v1/accounts/contacts/notes_controller.rb app/controllers/api/v1/accounts/contacts/labels_controller.rb app/controllers/api/v1/accounts/contacts/contact_inboxes_controller.rb app/controllers/api/v1/accounts/contacts/conversations_controller.rb app/controllers/api/v1/accounts/contacts/attachments_controller.rb app/controllers/api/v1/accounts/search_controller.rb app/services/search_service.rb app/controllers/api/v1/accounts/companies/contacts_controller.rb app/controllers/api/v1/accounts/actions/contact_merges_controller.rb app/controllers/api/v1/accounts/bulk_actions_controller.rb app/policies/data_import_policy.rb app/jobs/contacts/bulk_action_job.rb app/services/contacts/bulk_action_service.rb app/services/contacts/bulk_delete_service.rb app/jobs/data_import_job.rb app/jobs/avatar/avatar_from_gravatar_job.rb app/jobs/avatar/avatar_from_url_job.rb app/models/concerns/avatarable.rb app/services/contacts/company_association_service.rb app/models/concerns/contact_company_association.rb app/jobs/account/contacts_export_job.rb app/controllers/api/v1/accounts/contacts/avatar_downloads_controller.rb`

Run: `pnpm exec eslint app/javascript/dashboard/api/contacts.js app/javascript/dashboard/api/specs/contacts.spec.js app/javascript/dashboard/composables/usePolicy.js app/javascript/dashboard/composables/spec/usePolicy.spec.js app/javascript/dashboard/components-next/Contacts/ContactsCard/ContactsCard.vue app/javascript/dashboard/components-next/Contacts/Pages/ContactDetails.vue app/javascript/dashboard/components-next/Contacts/ContactsForm/ContactMergeForm.vue app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactMedia.vue app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsList.vue app/javascript/dashboard/routes/dashboard/contacts/components/ContactsBulkActionBar.vue`

Expected: PASS; protected links require authentication on every new Contacts download request, and legacy conversation/public/widget routes are unchanged.

- [x] **Step 6: Report Delivery 3 results to the user; Contacts remains planned.**

### Task 4: PostgreSQL validation, review report, and gated activation

**Files:**
- Modify: `app/services/rbac/catalog.rb` only after review approval
- Create: `docs/RBAC_STAGE2_CONTACTS_REVIEW.md`
- Test: all affected Contacts, RBAC, company, search, import/export, media, and job specs
- Test: `spec/requests/api/v1/accounts/contacts_rbac_concurrency_spec.rb` for PostgreSQL-backed cross-account/role-revocation interleavings

**Interfaces:**
- Before activation, deliver a review report with the requested endpoint matrix, permission map, test results, legacy compatibility, isolation evidence, and residual-risk analysis. It must include that old permanent Active Storage URLs already issued cannot be automatically revoked.
- Activation changes only the Contacts domain entries to `status: 'enforced'`, with the intended assignability; all other six modules stay planned.

- [x] **Step 1: Run PostgreSQL-backed concurrency and request/job tests for cross-account IDs, role/grant revocation, multi-account access, batch revocation, conversation filtering, and all endpoint mappings.** Use the task-specific disposable PostgreSQL cluster; do not use the host PostgreSQL service on port 5432.

Run: `eval "$(rbenv init -)"; bundle exec rspec spec/requests/api/v1/accounts/contacts_rbac_concurrency_spec.rb spec/requests/api/v1/accounts/contacts_rbac_spec.rb spec/requests/api/v1/accounts/data_imports_spec.rb spec/jobs/contacts/bulk_action_job_spec.rb spec/jobs/data_import_job_spec.rb spec/jobs/account/contacts_export_job_spec.rb`
- [x] **Step 2: Run the complete affected Ruby specs, Vue specs, RuboCop, and ESLint.** Record exact commands and results; do not mark unexecuted tests as passing.
- [x] **Step 3: Write `docs/RBAC_STAGE2_CONTACTS_REVIEW.md` with files, permissions, endpoint matrix, auxiliary operations, test results, legacy behavior, isolation evidence, residual risks, and recommendation.** Keep Contacts catalog entries planned.
- [x] **Step 4: Present the evidence from Deliveries 1–4 and request approval for the final Contacts-only catalog activation.** Do not activate before this user review.
- [x] **Step 5: After approval, change only Contacts catalog entries to enforced/assignable, rerun the catalog and authorizer specs, update the review report, and report the final status.** Completed after the user approved controlled activation; catalog, PostgreSQL, Vue, RuboCop, ESLint, and diff checks are recorded in `docs/RBAC_STAGE2_CONTACTS_REVIEW.md`.

