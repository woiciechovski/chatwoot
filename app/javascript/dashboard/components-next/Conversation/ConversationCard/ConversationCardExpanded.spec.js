import { shallowMount } from '@vue/test-utils';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import ConversationCardExpanded from './ConversationCardExpanded.vue';

describe('ConversationCardExpanded', () => {
  it('shows the conversation status below the activity time', () => {
    const wrapper = shallowMount(ConversationCardExpanded, {
      props: {
        chat: {
          id: 1,
          status: 'pending',
          timestamp: 1700000000,
          created_at: 1700000000,
          labels: [],
          messages: [],
          unread_count: 0,
        },
        currentContact: { name: 'Jane Doe' },
      },
      global: { mocks: { $t: key => key } },
    });
    const statusLabel = wrapper.find('[data-testid="conversation-status"]');
    const activityTime = wrapper.findComponent(TimeAgo);

    expect(statusLabel.text()).toBe(
      'CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.pending.TEXT'
    );
    expect(statusLabel.classes()).toContain('bg-n-amber-3');
    expect(
      activityTime.element.compareDocumentPosition(statusLabel.element)
    ).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
  });
});
