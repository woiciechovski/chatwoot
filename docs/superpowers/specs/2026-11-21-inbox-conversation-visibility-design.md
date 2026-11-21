# Inbox conversation visibility

## Intent

Let an account administrator restrict conversation access per inbox, without requiring Enterprise Custom Roles. This is for accounts where inbox membership alone is too broad: agents should see conversations assigned to them, conversations where they participate, and conversations assigned to one of their teams.

## Goals

- Add an inbox-level visibility mode that is available in OSS and Enterprise.
- In restricted mode, an inbox member agent can access a conversation when at least one condition is true:
  - the conversation is assigned to that agent;
  - the agent is a conversation participant, including through a valid private-note mention;
  - the conversation is assigned to a team the agent belongs to.
- Keep inbox membership as a required outer boundary for agents. Team membership alone does not grant access to an inbox.
- Keep administrators' current broad access.
- Make the restricted inbox mode cap Enterprise agent permissions, including `conversation_manage`; narrower Enterprise permissions may still narrow access further.
- Keep current visibility behavior for existing inboxes by defaulting the setting to `all`.

## Non-goals

- Change how inbox membership is granted or how conversations are auto-assigned.
- Make public message text count as a mention. Existing private-note mention behavior remains the source of participant records.
- Change administrator or AgentBot access behavior.
- Introduce account-wide access modes or require Custom Roles.

## Current behavior

Inbox membership determines which inboxes regular agents can access, and regular agents can list all conversations in those inboxes. Enterprise Custom Roles can narrow agent access to all, unassigned and own, or participating and own conversations, but they do not include team-assigned conversations. The inbox assignment policy controls automatic assignment, not conversation visibility. Direct conversation reads currently also allow team membership, which is not consistently represented in the list scope.

## Approaches

1. **Enterprise Custom Role permission:** rejected because it would make the feature unavailable to OSS users and configure it at the account role level rather than the inbox where the access boundary is managed.
2. **Change the existing participating permission:** rejected because it changes the meaning of an existing permission and may broaden access for agents already assigned that role.
3. **Inbox-level visibility mode:** selected. It matches the requested location, works without Enterprise, and preserves existing behavior until an administrator opts an inbox into restricted mode.

## Proposed behavior

Add an inbox setting with two modes: `all` and `assigned_participating_or_team`. The restricted mode label should read “Agents can manage conversations assigned to them, they participate in, or assigned to their teams.” The setting should live with inbox agent/access settings, separate from automatic assignment policy.

For an agent, effective access is the intersection of:

1. membership in the inbox;
2. the inbox visibility mode; and
3. any narrower Enterprise Custom Role permissions, when present.

In restricted mode, the inbox rule is `assigned_to_current_agent OR participant_is_current_agent OR conversation_team_is_one_of_current_agent_teams`. A Custom Role permission cannot broaden this inbox rule; `conversation_manage` therefore does not bypass it. Administrators retain their existing unrestricted access. In `all` mode, OSS behavior remains unchanged and Enterprise Custom Roles continue to apply as they do today.

## Surfaces to align

- Inbox model, API parameters/serialization, settings UI, and English source strings.
- The shared conversation permission filter used by conversation lists, advanced filters, and permission-scoped consumers.
- Direct conversation reads through `ConversationPolicy`, so a hidden conversation cannot be opened through a known URL or API ID.
- Search, contact conversation history, attachments, bulk actions, notifications, and any other consumer that lists or reads conversations outside the main inbox list.
- Frontend filtering for assignee/team views, mentions/participating views, and realtime conversation updates.
- Unread counts and cached visibility data so sidebar counts do not reveal conversations excluded by the new mode; invalidate affected caches when the mode or inbox membership changes.

## Validation expectations

Cover restricted and `all` inboxes; own assignment; another agent's assignment; participation from a private mention; team assignment for a member; team assignment for a non-member; an inbox non-member who is a team member; administrators; and an Enterprise agent with `conversation_manage`. Verify list and direct-read behavior agree, and verify inbox/team/mention counts match visible rows. Preserve existing behavior for conversations in inboxes that remain in `all` mode.

## Decisions made for this draft

- Inbox membership remains required even when an agent belongs to the assigned team, because the feature is configured inside an inbox.
- The new inbox mode acts as a maximum access boundary; an Enterprise Custom Role may further restrict, but cannot broaden it.
- The default is `all` to avoid changing existing inbox visibility until explicitly configured.
