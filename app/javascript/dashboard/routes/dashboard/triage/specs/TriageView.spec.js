import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import triageAPI from 'dashboard/api/triage';
import ConversationBasicFilter from 'dashboard/components/widgets/conversation/ConversationBasicFilter.vue';
import TriageView from '../TriageView.vue';
import TransferPanel from '../TransferPanel.vue';

const conversation = {
  id: 33,
  inbox_id: 4,
  meta: { sender: { id: 12, name: 'Taylor' } },
  messages: [{ id: 42, content: 'Help, please' }],
};
const queueItem = {
  execution: {
    id: 9,
    status: 'reserved',
    reserved_at: '2026-11-20T15:00:00Z',
    flow: { name: 'Returns' },
  },
  conversation: {
    id: 33,
    meta: { sender: { name: 'Taylor' } },
    messages: [{ content: 'Help, please' }],
  },
};

vi.mock('dashboard/api/triage', () => ({
  default: {
    get: vi.fn(),
    transfer: vi.fn(),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
  useStore: vi.fn(),
}));

vi.mock('dashboard/composables/useContactConversationNavigation', () => ({
  CONTACT_CONVERSATION_NAVIGATION: 'contactConversationNavigation',
  useContactConversationNavigation: () => ({}),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const queueResponse = items => ({
  data: {
    data: {
      meta: { current_page: 1, total_pages: 1, total_count: items.length },
      payload: items,
    },
  },
});

describe('TriageView', () => {
  let dispatch;
  let currentChat;
  let inboxes;
  let teams;
  let wrappers;

  beforeEach(() => {
    vi.clearAllMocks();
    wrappers = [];
    dispatch = vi.fn(async (action, payload) => {
      if (action === 'getConversation') currentChat.value = conversation;
      if (action === 'setActiveChat') currentChat.value = payload.data;
      if (action === 'clearSelectedState') currentChat.value = {};
    });
    currentChat = ref({});
    inboxes = ref([{ id: 4, name: 'Support' }]);
    teams = ref([{ id: 7, name: 'Returns team' }]);
    useStore.mockReturnValue({ dispatch });
    useMapGetter.mockImplementation(key => {
      if (key === 'inboxes/getInboxes') return inboxes;
      if (key === 'teams/getTeams') return teams;
      if (key === 'getSelectedChat') return currentChat;
      if (key === 'getConversationById') return ref(() => conversation);
      return ref([]);
    });
    triageAPI.get.mockResolvedValue(queueResponse([queueItem]));
    triageAPI.transfer.mockResolvedValue({ data: {} });
  });

  const mountComponent = () => {
    const wrapper = mount(TriageView, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          ConversationBox: {
            name: 'ConversationBox',
            props: { readOnly: Boolean },
            template: '<div data-testid="conversation-box"><slot /></div>',
          },
          ConversationBasicFilter: true,
          Button: {
            props: ['label', 'disabled', 'isLoading'],
            emits: ['click'],
            template:
              '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
          },
        },
      },
    });
    wrappers.push(wrapper);
    return wrapper;
  };

  afterEach(() => {
    wrappers.forEach(wrapper => wrapper.unmount());
    expect(emitter.all.get(BUS_EVENTS.TRIAGE_QUEUE_REFRESH) || []).toHaveLength(
      0
    );
    expect(emitter.all.get(BUS_EVENTS.WEBSOCKET_RECONNECT) || []).toHaveLength(
      0
    );
  });

  it('requests the sort selected in the native conversation menu', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(triageAPI.get).toHaveBeenLastCalledWith(
      expect.objectContaining({ sort_by: 'last_activity_at_asc' }),
      expect.anything()
    );

    wrapper
      .getComponent(ConversationBasicFilter)
      .vm.$emit('update:sortBy', 'last_activity_at_desc');
    await flushPromises();

    expect(triageAPI.get).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 1, sort_by: 'last_activity_at_desc' }),
      expect.anything()
    );
    expect(dispatch).not.toHaveBeenCalledWith(
      'setChatSortFilter',
      'last_activity_at_desc'
    );
  });

  it('loads the native conversation in read-only mode for triage', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await wrapper.find('button[aria-pressed="false"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('getConversation', 33);
    expect(dispatch).toHaveBeenCalledWith('setActiveChat', {
      data: conversation,
    });
    expect(wrapper.find('[data-testid="conversation-box"]').exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'ConversationBox' }).props('readOnly')
    ).toBe(true);
    expect(wrapper.findComponent(TransferPanel).props('contact')).toEqual(
      conversation.meta.sender
    );
    expect(wrapper.findComponent(TransferPanel).props('inboxName')).toBe(
      'Support'
    );
  });

  it('removes the conversation after a successful transfer', async () => {
    triageAPI.get
      .mockResolvedValueOnce(queueResponse([queueItem]))
      .mockResolvedValueOnce(queueResponse([]));
    const wrapper = mountComponent();
    await flushPromises();
    await wrapper.find('button[aria-pressed="false"]').trigger('click');
    await flushPromises();
    const transferPanel = wrapper.findComponent(TransferPanel);
    await transferPanel.find('select').setValue('7');
    await transferPanel.find('button').trigger('click');
    await flushPromises();

    expect(triageAPI.transfer).toHaveBeenCalledWith(33, '7');
    expect(wrapper.text()).toContain('TRIAGE.EMPTY');
  });

  it('keeps the selected item in triage when transfer fails', async () => {
    triageAPI.transfer.mockRejectedValue({
      response: { data: { error: 'Transfer rejected' } },
    });
    const wrapper = mountComponent();
    await flushPromises();
    await wrapper.find('button[aria-pressed="false"]').trigger('click');
    await flushPromises();
    wrapper.findComponent(TransferPanel).vm.$emit('transfer', '7');
    await flushPromises();

    expect(triageAPI.transfer).toHaveBeenCalledWith(33, '7');
    expect(wrapper.find('button[aria-pressed="true"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="conversation-box"]').exists()).toBe(
      true
    );
  });

  it('refreshes the queue when an administrator event arrives', async () => {
    mountComponent();
    await flushPromises();
    const requestsBeforeRefresh = triageAPI.get.mock.calls.length;
    emitter.emit(BUS_EVENTS.TRIAGE_QUEUE_REFRESH);
    await new Promise(resolve => {
      setTimeout(resolve, 300);
    });
    await flushPromises();

    expect(triageAPI.get).toHaveBeenCalledTimes(requestsBeforeRefresh + 1);
  });
});
