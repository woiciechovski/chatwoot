import { shallowMount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

const defaultChat = {
  id: 1,
  labels: [],
  messages: [],
  priority: null,
  unread_count: 0,
  timestamp: 1700000000,
  created_at: 1700000000,
};

const mountComponent = (chat, currentContact = {}, props = {}) =>
  shallowMount(ConversationCard, {
    props: {
      chat: { ...defaultChat, ...chat },
      currentContact: {
        name: 'Jane Doe',
        thumbnail: '',
        availability_status: 'offline',
        ...currentContact,
      },
      inbox: { id: 1 },
      ...props,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        'fluent-icon': true,
        InboxName: false,
      },
    },
  });

describe('ConversationCard', () => {
  it('does not reserve the labels row when only a persisted SLA policy id is present', () => {
    const wrapper = mountComponent({ sla_policy_id: 1, applied_sla: null });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('shows the labels row when an active applied SLA is present', () => {
    const wrapper = mountComponent({
      sla_policy_id: 1,
      applied_sla: { id: 1 },
    });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(true);
  });

  it('does not reserve the labels row when the contact is blocked', () => {
    const wrapper = mountComponent(
      {
        sla_policy_id: 1,
        applied_sla: { id: 1 },
      },
      { blocked: true }
    );

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('uses the bot icon for a Captain assignee', () => {
    const wrapper = mountComponent(
      { meta: { assignee_type: 'Captain::Assistant' } },
      {},
      { showAssignee: true, assignee: { name: 'Captain' } }
    );

    expect(wrapper.findComponent({ name: 'Icon' }).props('icon')).toBe(
      'i-lucide-bot'
    );
  });

  it('shows the channel and assignment on one line with the full label available', () => {
    const label = 'WhatsApp Evolution · Comercial · Ana';
    const wrapper = mountComponent(
      {},
      {},
      {
        inbox: { id: 1, name: 'WhatsApp Evolution' },
        inboxLabel: label,
        showInboxName: true,
      }
    );

    expect(wrapper.get(`[title="${label}"]`).text()).toBe(label);
  });

  it.each([
    ['open', 'bg-n-teal-3'],
    ['resolved', 'bg-n-slate-3'],
    ['pending', 'bg-n-amber-3'],
    ['snoozed', 'bg-n-blue-3'],
  ])('shows the %s status below the activity time', (status, color) => {
    const wrapper = mountComponent({ status });
    const statusLabel = wrapper.find('[data-testid="conversation-status"]');
    const activityTime = wrapper.findComponent({ name: 'TimeAgo' });

    expect(statusLabel.text()).toBe(
      `CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${status}.TEXT`
    );
    expect(statusLabel.classes()).toContain(color);
    expect(
      activityTime.element.compareDocumentPosition(statusLabel.element)
    ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
  });
});
