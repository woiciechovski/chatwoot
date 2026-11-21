# Conversation Flows and Triage Design

## Intent

Add a Community module that lets account administrators configure inbox flows, reserve eligible native conversations for triage, inspect their messages, and route them to an existing team. The feature keeps using Chatwoot `Conversation`, `Message`, inbox, and assignment behavior. Agents must not see reserved conversations through APIs, lists, search, counts, notifications, or real-time broadcasts.

## Goals

- Persist flow configuration and one auditable execution per conversation.
- Reserve new externally-created conversations before post-commit events and reserve eligible incoming messages on existing conversations before their post-commit events.
- Keep a reservation active when its flow is disabled and never reopen a completed execution on later messages.
- Give only account administrators access to flow configuration and triage.
- Reuse native conversation/message reads and team assignment for the admin workflow.
- Filter reserved conversations from agents' normal read paths, notifications, events, and unread counts.
- Keep accounts without enabled flows on the existing path.

## Non-goals

No visual flow editor, automation engine, bot/AI integration, new message/conversation store, advanced SLA or reporting, or Enterprise-only implementation.

## Constraints

- Follow the repository's Ruby, Rails, Vue, API, and translation patterns.
- Add no dependency and keep Flow Manager behavior in Community code. Update Enterprise overrides where they replace a Community query changed by this feature.
- All public queries and writes remain scoped to `Current.account`.
- Use ActiveRecord/Arel, bounded and paginated list queries, and native team assignment.
- Reservation changes must commit before conversation/message after-commit dispatch.

## Approaches considered

1. **Reserve only from `ConversationBuilder`.** Small change, but misses direct model creation in channel services and incoming messages on existing conversations. Rejected because the specification explicitly requires more than that path.
2. **Schedule a job to route conversations after message creation.** Covers asynchronous providers, but creates a window where existing create/message events can reach agents. Rejected because it violates the no-exposure requirement.
3. **Reserve synchronously in shared model lifecycle hooks and enforce the reservation centrally.** Covers direct conversation creation and all persisted incoming `Message` paths, while transactionally committing the reservation before post-commit events. Chosen because it uses native records and closes the exposure window. The implementation will also check eligibility before reserving an existing conversation so unrelated later messages do not move already-handled conversations back to triage.

## Data model

- `ConversationFlow` belongs to an account and records name, description, enabled state, creator, and last updater.
- `Inbox` has an optional `conversation_flow_id`; a flow may own multiple inboxes, and an inbox points to at most one flow at a time. This is a deliberately stronger, simpler invariant than allowing several inactive mappings while preventing active conflicts. The single reference enforces one mapping structurally; a foreign key validates the target.
- `ConversationFlowExecution` belongs to the same account, conversation, and flow. A unique conversation reference gives one stable execution/history row per conversation. It records `reserved`, `transferring`, `failed`, or `completed`, reserve/transfer timestamps, destination team, transfer actor, and last failure details. `reserved`, `transferring`, and `failed` all keep the conversation protected; `completed` releases it permanently.
- Association validations verify account ownership for inboxes, conversations, flows, users, and teams. Foreign keys and database indexes support integrity, account/status triage pagination, and reservation lookups.

## Reservation and transfer

- A newly created conversation is reserved synchronously in its create transaction when its inbox flow is enabled and it is externally initiated (`Current.user` is absent). This runs before `after_create_commit` dispatches `conversation_created`.
- An incoming `Message` on an existing conversation checks for any prior execution. If none exists, it reserves only when the inbox flow is enabled and the conversation is not already assigned or previously handled by an outgoing response. The execution's unique conversation index and a conversation row lock make the operation idempotent under duplicate or concurrent delivery.
- Disabled or absent flows return immediately; completed executions are never reactivated.
- Automatic assignment candidate queries and model assignment validation exclude protected executions. The transfer service is the only assignment path allowed to change a protected conversation.
- Outgoing messages cannot be created while a conversation is protected; incoming customer messages remain allowed and continue to be recorded on the native conversation. The triage view is read-only apart from transfer.
- Transfer locks the execution/conversation, validates the account team, writes the native conversation team assignment, and marks the execution completed in one database transaction. Failure leaves the reservation protected and records an error; a later retry can attempt it again. Competing transfers serialize on the execution row, and a second attempt sees the completed state.

## Authorization, events, and counts

- `ConversationPolicy` denies agent access to reserved conversations by ID. `Conversations::PermissionFilterService` excludes them from normal list, search, contact, and company conversation relations for non-administrators.
- All triage/configuration endpoints require an account administrator and load records through the current account. Existing message endpoints remain usable by triage administrators because they already authorize the native conversation.
- The direct upload path receives the same conversation policy check. Native assignment endpoints cannot change a protected conversation outside triage.
- `ActionCableListener` sends protected conversation/message events only to account administrators (and the relevant contact channel where the event is part of the contact's own conversation). Events queued while reserved keep that restricted recipient list. Normal broadcasts resume after transfer.
- `NotificationListener` suppresses agent-facing creation/message notifications while protected. Unread count cache builds and refreshes omit protected conversations; the normal conversation list uses the same relation filter for counts.
- The triage API returns a paginated native conversation payload with flow/execution metadata and no eager loading of every message. The native conversation/message endpoints supply detail and history.

## Dashboard

- Add administrator-only navigation for **Triage** and **Settings → Flows**, backed by route metadata and the backend authorization above.
- Build a flow list and create/edit form using existing settings layout, form, status, inbox selector, toast, and empty-state patterns.
- Build triage as a queue around existing conversation card/message viewer components. Add a focused transfer panel using the account's native team list. The selected conversation is loaded through the existing conversation/message store; the triage list refreshes after transfer and receives administrator-only ActionCable updates.
- Add only English product strings in frontend `en.json` and backend `en.yml`.

## Audit

Flow rows retain creator, last updater, and timestamps. Each execution retains its reservation status, transfer actor, destination team, transfer time, and latest failure information. The native team update also emits Chatwoot's existing assignment activity. No parallel message or conversation history is introduced.

## Validation

Add focused model/service/API specs for flow ownership and active mapping, creation and incoming-message reservations, idempotency and transfer races, failed transfer recovery, policy/list/search/count isolation, notification and broadcast recipients, and native continuation after transfer. Add frontend tests for administrator routing, flow CRUD states, triage pagination/detail/transfer, and queue refresh. Run focused RSpec, Vitest, and RuboCop/ESLint checks for touched files; report any unavailable environment checks.
