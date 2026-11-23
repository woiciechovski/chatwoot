# RBAC Contacts Final Security Review Plan

> **For agentic workers:** Implement inline in the existing `feat/rbac-core` worktree. Follow TDD for the export authorization change. Do not commit the already-dirty branch.

**Goal:** Require both `contacts.read` and `contacts.export` for managed-agent exports, then record the requested final security review of Contacts.

**Architecture:** Keep `ContactPolicy#export?` as the shared gate used by the export request, job, download, and capabilities endpoint. For RBAC-managed agents it requires both grants; native administrator and unmanaged-agent behavior keeps the current policy fallback. The existing UI capability mechanism consumes the effective server capability, with an explicit all-of check for export. Conversation serialization remains unchanged.

**Tech Stack:** Rails, Pundit, Active Job, Vue 3, RSpec, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-22-rbac-contacts-design.md` plus the user’s final security review requirements dated 2026-11-23.

## Global Constraints

- Preserve the current `feat/rbac-core` work and do not edit `enterprise/`.
- Keep only the six Contacts permissions enforced; Companies and the other five domains stay planned.
- Preserve `rbac_managed`, native-admin, unmanaged-agent, account-isolation, and NestJS behavior.
- Do not alter Conversation, Message, Notification, WebSocket, or search serialization in this review.
- Do not add real-time revocation synchronization or begin another module.

## Review Focus

1. A managed role with only `contacts.export` must not enqueue, process, or download an export; verify request, job, download, capability, and UI behavior.
2. A role with `contacts.read` plus `contacts.export` must export successfully, while admin/unmanaged policy fallback remains unchanged.
3. Document PII embedded in conversation surfaces that remain governed by conversation access, and state that this review does not redact it.
4. Document CompanyPolicy legacy paths and dashboard revocation/cache/download limits without changing those contracts.

---

### Task 1: Enforce the combined export permission

**Files:** `app/policies/contact_policy.rb`, `app/javascript/dashboard/components-next/Contacts/ContactsHeader/components/ContactMoreActions.vue`, request/policy/job/capability/Vue specs.

**Tests first:** Add managed-agent cases proving export-only fails and read+export succeeds at ContactPolicy, export request, async job, authenticated download, capabilities, and the export menu. Preserve native administrator and unmanaged-agent expectations.

**Implementation:** Make the managed-agent branch of `ContactPolicy#export?` require both existing permissions. Make the export menu ask for both capabilities. Existing request, job, download, and capability code already delegates to `ContactPolicy` and should need no second authorization mechanism.

**Verification:** Run focused PostgreSQL-backed RSpec files for ContactPolicy, RBAC capabilities, contact export requests/downloads, and export job; run focused Vue tests for `usePolicy` and `ContactMoreActions`.

### Task 2: Clear protected caches after denied reads

**Files:** `app/javascript/dashboard/store/modules/contacts/actions.js`, new `app/javascript/dashboard/store/modules/contactReadCache.js`, `app/javascript/dashboard/store/modules/contactNotes.js`, `app/javascript/dashboard/store/modules/contactConversations.js`, and the matching action/mutation specs.

**Tests first:** Assert that `contacts.show` clears the namespaced contact-note cache, and that a 401/403 from Contacts, notes, contact history, or contact-conversation-neighbour reads clears Contact lists, notes, history, and neighbour caches. A non-authorization error must retain auxiliary-cache behavior.

**Implementation:** Correct the namespaced Vuex mutation target and clear the contact-specific cache synchronously on denied read responses. Do not add polling, push, or real-time revocation signals.

**Verification:** Run the modified Contacts, contact-notes, and contact-conversation action and mutation specs plus the export capability/menu Vue specs.

### Task 3: Complete the final review report

**Files:** `docs/RBAC_STAGE2_CONTACTS_REVIEW.md`.

**Review evidence:** Inspect conversation list/detail/history, message, websocket, notification, and global-search serializers and document their Contact fields that remain visible under Conversation access without `contacts.read`. Trace contact-driven CompanyPolicy checks and the legacy paths while Companies remains planned. Confirm dashboard denial-cache clearing, open-page revocation behavior, authenticated download limits, and old permanent URLs.

**Constraint:** Documentation only for conversation serialization, Companies activation, and real-time synchronization; no changes to those implementations.

**Verification:** Run Rails/Vue tests above, changed-file RuboCop/ESLint, and document whitespace/diff checks. Record results, limitations, residual risks, and recommendation for closing Stage 2.1.
