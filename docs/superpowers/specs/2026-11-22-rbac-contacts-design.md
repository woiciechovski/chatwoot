# RBAC Contacts Integration Design

## Intent

Integrate the existing `Rbac::Authorizer` into the authenticated Contacts module as the reference implementation for a future module. Managed agents must use explicit account-scoped permissions, while native administrators and unmanaged agents retain their existing behavior. The other six catalog domains stay `planned`; no Enterprise source is changed and no RBAC administration UI is added.

## Goals

- Enforce `contacts.read`, `contacts.create`, `contacts.update`, and `contacts.delete` on all authenticated Rails entry points that expose or mutate contacts.
- Keep reads account-scoped and preserve the existing inbox/conversation access filter for conversation history and attachments.
- Deny managed agents with no role or no matching grant; revoking a role or grant takes effect immediately, including for already-issued personal access tokens and queued jobs.
- Cover auxiliary writes, bulk actions, merges, imports, exports, and downloads without allowing `contacts.read` to authorize a mutation or export.
- Activate the Contacts catalog domain only after all covered paths and PostgreSQL tests pass.

## Non-goals and constraints

- Do not begin the other six module integrations, add an RBAC admin screen, change the NestJS/SaaS surface, or edit any `enterprise/` source.
- Preserve `rbac_managed` semantics, account isolation, Community compatibility, and current behavior for users not managed by RBAC.
- Do not replace the existing authorization engine with controller-specific rules or a second permission service.
- Public/widget contact APIs remain under their existing HMAC/token contract because they do not execute as an `AccountUser`.

## Approaches

1. **Extend `ContactPolicy` and reuse `Rbac::Authorizer` (selected).** This keeps the existing Pundit entry point and lets controllers use their normal authorization path. Jobs and direct paths that do not use Pundit will call the same policy/authorizer contract with the initiating account membership. Unmanaged users continue through existing policy behavior.
2. **Add permission checks separately in each controller.** This is rejected because nested controllers, search, bulk jobs, and export jobs could drift or bypass one another.
3. **Create a Contacts-specific authorization engine.** This is rejected because the request requires the existing authorizer to remain the sole source of RBAC grants.

## Permission mapping

- `contacts.read`: index, active, search, filter, show, contactable inbox lookup, label/note reads, attachments, and contact conversation history. Conversation results remain filtered by `Conversations::PermissionFilterService`. Global search omits its direct contacts result when this grant is absent while retaining conversation/message/article behavior under their existing rules.
- `contacts.create`: contact creation; optional inbox association also retains the existing Inbox policy.
- `contacts.update`: contact fields, labels, notes, custom-attribute removal, avatar removal, contact-inbox links, company membership changes through Contacts entry points, bulk label changes, and merge-base changes.
- `contacts.delete`: contact deletion and bulk contact deletion.
- Merge requires `contacts.read`, `contacts.update`, and `contacts.delete` for both contacts. It is denied when the initiating user cannot see all conversations attached to either contact, using the existing conversation permission filter. This avoids adding a separate `contacts.merge` key while protecting the destructive workflow and its conversation associations.
- Add assignable `contacts.import` and `contacts.export`, separate from CRUD grants. `contacts.import` covers contacts-only CSV and integration imports; imports that also include conversations stay under the existing administrator-only data-import policy. A managed agent may manage only their own contacts-only `DataImport` record (show/start/retry/abandon/logs) while the grant remains active. `contacts.export` covers creating an export and each authenticated download.
- Mutation permissions do not imply read permission. Managed agents without `contacts.read` receive only the fields needed to confirm their own create/update operation; response templates must not serialize existing contact data, labels, company records, or related conversations.

## Authorization and asynchronous work

- `ContactPolicy` maps its public actions to catalog permissions. Native administrators remain allowed. Non-managed agents retain current policy behavior. Managed agents are evaluated only through `Rbac::Authorizer` for the enforced Contacts domain.
- Account-scoped relations and existing nested lookup patterns remain the source of tenant boundaries. Cross-account contact IDs return not found or forbidden without changing data.
- A missing `AccountUser` is not authorization. User-initiated jobs persist account/user identity and re-resolve the active membership at run time. System-origin jobs must carry a code-controlled allowlisted origin plus a trusted principal identity (for example, a verified provider inbox ID, an HMAC-verified contact/inbox pair, or a specific scheduled worker identity); request parameters cannot supply either value. Missing, unknown, untrusted, or account-mismatched origin/principal fails closed.
- Bulk, CSV import, integration contact-import, export, and user-initiated avatar-fetch jobs re-evaluate the initiating `AccountUser` and permission before execution and between batches of at most 100 records. Revocation committed during a batch allows only that already-authorized batch to finish; the next batch stops. Import/export jobs then report failure and do not publish output; writes from previously committed batches are not rolled back. For avatar fetching, carry account/user identity through the `Contact#after_save` → `AvatarFromGravatarJob` → `AvatarFromUrlJob` chain, and recheck immediately before attaching the downloaded image.
- A contacts-only integration import requires `contacts.import` both at request time and in each worker page. Any integration request whose effective import types include conversations remains administrator-only. Missing import types retain the current defaults and therefore do not silently become contact-only. Import status/log access remains limited to the initiator while the contacts-only grant is active.
- Export download uses an authenticated account route that re-checks `contacts.export`; the existing reusable Active Storage export URL is not sent to recipients.
- Contact API responses use authenticated application routes for contact avatars and contact-aggregated attachments instead of returning Active Storage bearer URLs. Those routes check `contacts.read` and, for attachments, reapply the existing conversation permission filter before streaming through `ActiveStorage::Streaming`. The Contacts UI fetches these resources through its authenticated Axios client and uses local object URLs for previews/downloads. Conversation and public/widget responses keep their existing media behavior because those surfaces are governed by separate policies and are outside this module integration. Active Storage URLs issued by the pre-integration version remain permanent bearer URLs; the rollout cannot revoke links already copied from old responses, and the final review must record that legacy limitation.
- `contacts.update` authorizes mutations to Contact attributes only. Changing a company association must also pass the existing `CompanyPolicy` for that account; automatic Company creation caused by a contact create or first-email association must be explicitly authorized with `CompanyPolicy#create?` before the callback can write. This does not grant Company create/update/delete or any other module permission. Native and legacy behavior continues through the same Company policy.

## Frontend

No admin UI or redesign is in scope. Backend Rails authorization is authoritative. Extend the existing `/rbac/me/capabilities` response with effective Contacts permissions from the same `ContactPolicy`, expose them to the existing Vue `usePolicy` helper, and gate contact create/update/delete, label, import, and export controls. The merge control requires all of read, update, and delete (the existing helper's any-of check is insufficient). Use authenticated Axios fetches for Contact API avatars and attachment media, then revoke object URLs when the view or selected contact changes. Legacy account permissions remain intact for all other modules and unmanaged agents.

## Verification and activation

Deliver the work as four reviewable stages: (1) CRUD policy/catalog wiring, with Contacts still `planned`; (2) auxiliary operations and job authorization; (3) authenticated downloads and minimal Contacts UI capability gates; (4) PostgreSQL validation and, only after complete test coverage, catalog activation. The catalog remains `planned` and non-assignable throughout the first three stages.

Request, Vue, and job tests cover native administrator, legacy agent, managed agent with no grant, each CRUD permission alone, multiple grants, role/grant revocation, multi-account membership, reused API tokens, cross-account IDs, nested resources, global search, merge, bulk actions, imports/exports, job revocation at batch boundaries, trusted system origins, avatar callback propagation, and each integration import type. PostgreSQL concurrency tests exercise relevant concurrent membership and contact operations. Run focused specs, changed-file RuboCop/ESLint, and the PostgreSQL-backed suite for the final review. Present the evidence from all four stages before definitive activation of Contacts.
