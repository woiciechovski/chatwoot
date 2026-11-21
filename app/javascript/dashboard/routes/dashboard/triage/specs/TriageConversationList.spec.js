import { mount } from '@vue/test-utils';
import TriageConversationList from '../TriageConversationList.vue';

const queueItem = {
  execution: { id: 9, flow: { name: 'Returns' } },
  conversation: {
    id: 33,
    inbox_id: 4,
    timestamp: 1795188600,
    meta: { sender: { name: 'Taylor' } },
    messages: [{ content: 'I need help', created_at: 1795188600 }],
  },
};

const global = {
  mocks: { $t: key => key },
  stubs: { ConversationBasicFilter: true },
};

describe('TriageConversationList', () => {
  it('shows the selected conversation and emits selection and pagination', async () => {
    const wrapper = mount(TriageConversationList, {
      props: {
        items: [queueItem],
        selectedId: 33,
        page: 1,
        totalPages: 2,
        sortBy: 'last_activity_at_asc',
        inboxes: [{ id: 4, name: 'Support' }],
      },
      global,
    });

    const row = wrapper.find('button[aria-pressed="true"]');
    expect(row.text()).toContain('Taylor');
    expect(row.text()).toContain('I need help');
    expect(row.text()).toContain('Support');
    expect(row.find('time').attributes('datetime')).toBe(
      '2026-11-20T15:30:00.000Z'
    );
    await row.trigger('click');
    await wrapper.findAll('footer button')[1].trigger('click');

    expect(wrapper.emitted('select')[0][0]).toEqual(queueItem);
    expect(wrapper.emitted('pageChange')[0]).toEqual([2]);
  });

  it('emits search and inbox filter updates', async () => {
    const wrapper = mount(TriageConversationList, {
      props: {
        items: [],
        inboxes: [{ id: 4, name: 'Support' }],
        sortBy: 'last_activity_at_asc',
      },
      global,
    });

    await wrapper.find('input[type="search"]').setValue('Taylor');
    await wrapper.find('select').setValue('4');

    expect(wrapper.emitted('update:searchQuery')[0]).toEqual(['Taylor']);
    expect(wrapper.emitted('update:inboxId')[0]).toEqual(['4']);
  });
});
