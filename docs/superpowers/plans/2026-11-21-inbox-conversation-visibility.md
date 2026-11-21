# Inbox conversation visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let administrators restrict an inbox so agents can manage only conversations assigned to them, where they participate, or assigned to one of their teams.

**Architecture:** Add a string access mode to Inbox, defaulting to `all`, and expose it in inbox settings. Apply the restricted mode in the shared conversation permission scope and direct-read policy; keep inbox membership as a required boundary and let Enterprise roles narrow, but never broaden, that access. Align counts, notifications, and realtime recipients with the same visibility rule.

**Tech Stack:** Rails, ActiveRecord/Arel, RSpec, Vue 3 Composition API, Vuex, Vitest, ESLint.

**Spec:** `docs/superpowers/specs/2026-11-21-inbox-conversation-visibility-design.md`

## Global Constraints

- The new mode is available in OSS and Enterprise.
- Supported modes are `all` and `assigned_participating_or_team`; the default is `all`.
- Restricted inbox access is the intersection of inbox membership and assignment to the agent, participation by the agent, or assignment to one of the agent's teams.
- Administrators retain broad access; AgentBot behavior stays unchanged.
- Enterprise Custom Roles can narrow the inbox rule, but cannot broaden it; `conversation_manage` cannot bypass it.
- Use Rails/Arel for production queries; keep queries tenant-scoped and bounded.
- Add meaningful behavior tests, including Enterprise behavior, and update only English source strings.

## Review Focus

- A team member who is not an inbox member must not gain access through the team assignment — pin in permission scope and direct policy tests.
- A Custom Role with `conversation_manage` must not broaden a restricted inbox — pin in Enterprise permission-scope and policy tests.
- Changing the mode must refresh user-specific unread snapshots — pin in Inbox callback and unread counter tests.
- Existing notifications and queued email/push jobs must not expose a conversation after access is restricted — pin in finder and delivery tests.
- Realtime events must not publish restricted conversation data to unrelated inbox members — pin in broadcast-recipient tests.

---

### Task 1: Persist, expose, and configure inbox access mode

**Files:**
- Create: migration generated with `bundle exec rails g migration AddAgentConversationAccessToInboxes agent_conversation_access:string`
- Modify: `app/models/inbox.rb`
- Modify: `app/controllers/api/v1/accounts/inboxes_controller.rb`
- Modify: `app/views/api/v1/models/_inbox.json.jbuilder`
- Modify: `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/CollaboratorsPage.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json`
- Test: `spec/models/inbox_spec.rb`
- Test: `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb`
- Test: `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/specs/CollaboratorsPage.spec.js`

**Interfaces:**
- Produces: `Inbox#agent_conversation_access`, with `all` as database and model default; `Inbox#restricted_agent_conversation_access?`; API field `agent_conversation_access`.

- [ ] **Step 1: Write failing model and API tests** for default `all`, accepted values, rejection of unknown values, update persistence, and API serialization.
- [ ] **Step 2: Run the focused model and controller specs.** Expected: fail because the access mode does not exist or is not accepted/serialized.
- [ ] **Step 3: Generate and implement the migration, model validation/helper, permitted API field, and serializer field.** Set the migration column non-null with default `all`.
- [ ] **Step 4: Run the same focused specs.** Expected: pass.
- [ ] **Step 5: Add a failing frontend test** proving the inbox collaborators settings show a disabled-by-default access toggle and send the restricted mode when enabled.
- [ ] **Step 6: Run the focused Vitest spec.** Expected: fail because the control is absent.
- [ ] **Step 7: Add the access toggle and English strings to the collaborators settings.** Save through `inboxes/updateInbox` using `agent_conversation_access`.
- [ ] **Step 8: Run the focused Vitest spec and ESLint on the changed Vue file.** Expected: pass with no errors.

### Task 2: Enforce visibility in lists, direct reads, and Enterprise roles

**Files:**
- Modify: `app/services/conversations/permission_filter_service.rb`
- Modify: `app/policies/conversation_policy.rb`
- Modify: `enterprise/app/services/enterprise/conversations/permission_filter_service.rb` only if needed to preserve the restricted inbox ceiling
- Modify: `enterprise/app/policies/enterprise/conversation_policy.rb` only if needed to preserve the restricted inbox ceiling
- Test: `spec/services/conversations/permission_filter_service_spec.rb`
- Test: `spec/policies/conversation_policy_spec.rb`
- Test: `spec/enterprise/services/enterprise/conversations/permission_filter_service_spec.rb`
- Test: `spec/enterprise/policies/conversation_policy_spec.rb`

**Interfaces:**
- Consumes: `Inbox#restricted_agent_conversation_access?` from Task 1.
- Produces: a shared permission scope that enforces membership plus own assignment, participation, or assigned team in restricted inboxes.

- [ ] **Step 1: Add failing scope and policy examples** for own assignment, another agent's assignment, participation, team assignment, non-member team access, inbox non-member access, administrators, `all` mode, and Enterprise `conversation_manage`.
- [ ] **Step 2: Run the four focused specs.** Expected: failures show list and direct-read behavior currently do not implement the inbox rule.
- [ ] **Step 3: Apply the restricted inbox predicate in `PermissionFilterService` while preserving `plan_hint_selective_filter`; update `ConversationPolicy` so restricted inboxes require membership and one allowed relationship.** Keep administrator and AgentBot paths unchanged.
- [ ] **Step 4: Confirm Enterprise's custom-role filters consume the capped core scope and its policy calls the capped core policy.** Change Enterprise files only if the tests demonstrate a bypass.
- [ ] **Step 5: Run the four focused specs.** Expected: pass, including `conversation_manage` denial for unrelated restricted conversations.

### Task 3: Align unread counts and invalidate user snapshots

**Files:**
- Create: `app/services/conversations/unread_counts/inbox_scoped_counter.rb`
- Modify: `app/services/conversations/unread_counts/counter.rb`
- Modify: `app/models/inbox.rb`
- Test: `spec/services/conversations/unread_counts/inbox_scoped_counter_spec.rb`
- Test: `spec/services/conversations/unread_counts/counter_spec.rb`
- Test: `spec/models/inbox_spec.rb`

**Interfaces:**
- Consumes: `Conversations::PermissionFilterService` and `Inbox#restricted_agent_conversation_access?`.
- Produces: SQL-grouped unread inbox, label, and team counts from conversations visible to the current user; `Counter` uses it only when an agent belongs to at least one restricted inbox.

- [ ] **Step 1: Write failing count tests** for team-assigned/participating conversations and hidden assignments, plus a mode-change test for per-user filtered-count invalidation.
- [ ] **Step 2: Run the focused counter and Inbox specs.** Expected: current shared counts include conversations hidden by the restricted mode and mode changes do not bump the member's filtered count version.
- [ ] **Step 3: Implement the scoped unread relation and grouped counts; branch to it for agents with restricted inboxes.** Keep admins and all-mode agents on existing cache behavior.
- [ ] **Step 4: Capture inbox member IDs before a mode update and invalidate their filtered unread snapshots after commit.** Inbox membership changes continue using the existing `InboxMember` invalidator.
- [ ] **Step 5: Run the focused count and Inbox specs.** Expected: counts match visible conversations and the member's snapshot version changes on mode updates.

### Task 4: Align notifications and realtime delivery

**Files:**
- Modify: `app/finders/notification_finder.rb`
- Modify: `app/services/notification/email_notification_service.rb`
- Modify: `app/services/notification/push_notification_service.rb`
- Modify: `app/listeners/conversation_flow_broadcasts.rb`
- Modify: `app/services/conversations/unread_counts/broadcast_scope.rb`
- Test: `spec/finders/notification_finder_spec.rb`
- Test: `spec/services/notification/email_notification_service_spec.rb`
- Test: `spec/services/notification/push_notification_service_spec.rb`
- Test: `spec/listeners/action_cable_listener_spec.rb`
- Test: `spec/services/conversations/unread_counts/broadcast_scope_spec.rb`

**Interfaces:**
- Consumes: Task 1's inbox mode and Task 2's capped permission scope.
- Produces: notification listings, delayed deliveries, conversation broadcasts, and unread-count broadcasts that exclude agents who cannot access a restricted conversation.

- [ ] **Step 1: Write failing tests** showing a prior notification is hidden, queued email/push delivery is skipped after visibility is restricted, and realtime recipients exclude unrelated inbox members while retaining eligible agents and administrators.
- [ ] **Step 2: Run the focused finder, service, and listener specs.** Expected: failures because the current paths target all existing notifications or inbox members.
- [ ] **Step 3: Filter existing conversation notifications using the restricted inbox conversation scope; re-check direct policy access before delayed email/push delivery.** Leave non-conversation notifications and all-mode behavior unchanged.
- [ ] **Step 4: Limit realtime recipients to inbox members satisfying the restricted assignment/participant/team rule; preserve admin and reserved-flow behavior.** Keep recipient selection query-based.
- [ ] **Step 5: Run the focused finder, delivery, listener, and broadcast-scope specs.** Expected: pass with no restricted conversation data sent to unrelated agents.

### Task 5: Whole-feature verification and review

**Files:** all files changed by Tasks 1–4.

**Interfaces:** all interfaces above.

- [ ] **Step 1: Run focused RSpec for all new/changed backend specs and RuboCop for changed Ruby files.** Expected: pass; report any environment limitation with its exact cause.
- [ ] **Step 2: Run focused Vitest and ESLint for changed frontend files.** Expected: pass with no lint errors.
- [ ] **Step 3: Review the full diff against the spec**, including API/direct-read parity, Enterprise overrides, notifications, realtime, unread counts, default behavior, and query scope.
- [ ] **Step 4: Run `git diff --check` and confirm the main worktree contains only intended changes.** Expected: clean check and no unrelated edits.
