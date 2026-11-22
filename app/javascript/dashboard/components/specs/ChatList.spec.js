import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import ChatList from '../ChatList.vue';
import ChatListHeader from '../ChatListHeader.vue';
import ConversationList from '../ConversationList.vue';
import ChatTypeTabs from '../widgets/ChatTypeTabs.vue';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  updateUISettings: vi.fn(),
  resetUISettings: null,
  routerPush: vi.fn(),
  routerReplace: vi.fn(),
}));
const mineConversations = [
  { id: 1, status: 'open', last_activity_at: 10, created_at: 10, meta: {} },
  { id: 2, status: 'open', last_activity_at: 30, created_at: 30, meta: {} },
];

vi.mock('vuex', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useStore: () => ({ dispatch: mocks.dispatch }),
  };
});

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: mocks.routerPush, replace: mocks.routerReplace }),
  useRoute: () => ({ query: {} }),
}));

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: vi.fn(),
  useFunctionGetter: vi.fn(),
}));

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref: createRef } = await import('vue');
  const uiSettings = createRef({});
  mocks.resetUISettings = settings => {
    uiSettings.value = settings;
  };

  return {
    useUISettings: () => ({
      uiSettings,
      updateUISettings: settings => {
        const result = mocks.updateUISettings(settings);
        uiSettings.value = { ...uiSettings.value, ...settings };
        return result;
      },
    }),
  };
});

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));

vi.mock('dashboard/composables/chatlist/useBulkActions', async () => {
  const { ref: createRef } = await import('vue');
  return {
    useBulkActions: () => ({
      selectedConversations: createRef([]),
      selectedInboxes: createRef([]),
      selectConversation: vi.fn(),
      deSelectConversation: vi.fn(),
      selectAllConversations: vi.fn(),
      resetBulkActions: vi.fn(),
      isConversationSelected: vi.fn(() => false),
      onAssignAgent: vi.fn(),
      onAssignLabels: vi.fn(),
      onRemoveLabels: vi.fn(),
    }),
  };
});

vi.mock('shared/composables/useFilter', () => ({
  useFilter: () => ({
    initializeStatusAndAssigneeFilterToModal: vi.fn(),
    initializeInboxTeamAndLabelFilterToModal: vi.fn(() => []),
  }),
}));

vi.mock('dashboard/composables/useTransformKeys', () => ({
  useCamelCase: value => value,
  useSnakeCase: value => value,
}));

vi.mock('dashboard/composables/emitter', () => ({
  useEmitter: vi.fn(),
}));

vi.mock('dashboard/composables/useConversationRequiredAttributes', () => ({
  useConversationRequiredAttributes: () => ({
    checkMissingAttributes: () => ({ hasMissing: false }),
  }),
}));

vi.mock('dashboard/composables/useConversationRoutePath', () => ({
  useConversationRoutePath: () => ({
    buildConversationPath: vi.fn(),
    buildConversationListPath: vi.fn(),
  }),
}));

vi.mock('dashboard/helper/permissionsHelper.js', () => ({
  getUserPermissions: () => [],
  filterItemsByPermission: items =>
    Object.entries(items).map(([key, item]) => ({ key, ...item })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('ChatList', () => {
  let wrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.resetUISettings({});
    mocks.updateUISettings.mockResolvedValue(undefined);
    mocks.dispatch.mockResolvedValue(undefined);
    useMapGetter.mockImplementation(key => {
      const getters = {
        getAppliedConversationFiltersQuery: [],
        getCurrentUser: { id: 1, name: 'Agent' },
        getFilteredConversations: [],
        getMineChats: filters =>
          mineConversations.filter(
            conversation =>
              filters.status === 'all' || conversation.status === filters.status
          ),
        getAllStatusChats: () => [],
        getUnAssignedChats: () => [],
        getParticipatingChats: () => [],
        getChatListLoadingStatus: false,
        getSelectedInbox: {},
        'conversationStats/getStats': {
          mineCount: 0,
          unAssignedCount: 0,
          allCount: 0,
        },
        getAppliedConversationFiltersV2: [],
        getAppliedContactFilter: null,
        'customViews/getConversationCustomViews': [],
        'agents/getAgents': [],
        'teams/getTeams': [],
        'inboxes/getInboxes': [],
        'campaigns/getAllCampaigns': [],
        'labels/getLabels': [],
        getCurrentAccountId: 1,
        'teams/getTeam': () => ({}),
        getConversationById: () => undefined,
        'contacts/getContact': () => undefined,
      };
      return ref(getters[key]);
    });
    useFunctionGetter.mockImplementation(key => {
      const getters = {
        'inboxes/getInbox': {},
        'conversationPage/getCurrentPageFilter': 0,
        'conversationPage/getHasEndReached': false,
        'conversationStats/getCountsByStatus': {
          open: { mineCount: 4, unAssignedCount: 2, allCount: 6 },
          pending: { mineCount: 1, unAssignedCount: 3, allCount: 4 },
          all: { mineCount: 10, unAssignedCount: 6, allCount: 16 },
        },
        'attributes/getAttributesByModel': [],
      };
      return ref(getters[key]);
    });

    wrapper = shallowMount(ChatList, {
      global: { mocks: { $t: key => key } },
    });
  });

  afterEach(() => {
    wrapper.unmount();
  });

  it('keeps the other tabs counting their own status when All is selected', async () => {
    const tabs = wrapper.getComponent(ChatTypeTabs);
    const counts = () => tabs.props('items').map(({ count }) => count);

    expect(counts()).toEqual([4, 3, 16]);

    tabs.vm.$emit('chatTabChange', 'all');
    await flushPromises();

    expect(counts()).toEqual([4, 3, 16]);
    expect(mocks.dispatch).toHaveBeenCalledWith(
      'updateChatListFilters',
      expect.objectContaining({ tabStatuses: ['open', 'pending', 'all'] })
    );
  });

  it('keeps status and sort preferences independent across assignee tabs', async () => {
    await flushPromises();
    const header = wrapper.getComponent(ChatListHeader);
    const tabs = wrapper.getComponent(ChatTypeTabs);

    expect(header.props('activeStatus')).toBe('open');
    expect(header.props('activeSortBy')).toBe('last_activity_at_desc');

    header.vm.$emit('basicFilterChange', 'unresolved', 'status');
    header.vm.$emit('basicFilterChange', 'last_activity_at_asc', 'sort');
    await flushPromises();

    tabs.vm.$emit('chatTabChange', 'unassigned');
    await flushPromises();

    expect(header.props('activeStatus')).toBe('pending');
    expect(header.props('activeSortBy')).toBe('last_activity_at_desc');
    expect(mocks.dispatch).toHaveBeenCalledWith(
      'updateChatListFilters',
      expect.objectContaining({
        assigneeType: 'unassigned',
        status: 'pending',
        sortBy: 'last_activity_at_desc',
      })
    );

    header.vm.$emit('basicFilterChange', 'snoozed', 'status');
    header.vm.$emit('basicFilterChange', 'created_at_asc', 'sort');
    await flushPromises();

    tabs.vm.$emit('chatTabChange', 'all');
    await flushPromises();
    expect(header.props('activeStatus')).toBe('all');
    expect(header.props('activeSortBy')).toBe('last_activity_at_desc');

    tabs.vm.$emit('chatTabChange', 'me');
    await flushPromises();

    expect(header.props('activeStatus')).toBe('unresolved');
    expect(header.props('activeSortBy')).toBe('last_activity_at_asc');
    expect(mocks.updateUISettings).toHaveBeenCalledWith(
      expect.objectContaining({
        conversation_list_filters: expect.objectContaining({
          me: { status: 'unresolved', sort_by: 'last_activity_at_asc' },
          unassigned: { status: 'snoozed', sort_by: 'created_at_asc' },
        }),
      })
    );

    wrapper.unmount();
    wrapper = shallowMount(ChatList, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();

    const restoredHeader = wrapper.getComponent(ChatListHeader);
    expect(restoredHeader.props('activeStatus')).toBe('unresolved');
    expect(restoredHeader.props('activeSortBy')).toBe('last_activity_at_asc');

    wrapper.getComponent(ChatTypeTabs).vm.$emit('chatTabChange', 'unassigned');
    await flushPromises();

    expect(restoredHeader.props('activeStatus')).toBe('snoozed');
    expect(restoredHeader.props('activeSortBy')).toBe('created_at_asc');
  });

  it('sorts the active tab list by its selected order', async () => {
    await flushPromises();
    const list = wrapper.getComponent(ConversationList);

    expect(
      list.props('conversationList').map(conversation => conversation.id)
    ).toEqual([2, 1]);

    wrapper
      .getComponent(ChatListHeader)
      .vm.$emit('basicFilterChange', 'last_activity_at_asc', 'sort');
    await flushPromises();

    expect(
      list.props('conversationList').map(conversation => conversation.id)
    ).toEqual([1, 2]);
  });

  it('uses tab defaults when only a shared status was saved', async () => {
    wrapper.unmount();
    mocks.resetUISettings({
      conversations_filter_by: {
        status: 'resolved',
        order_by: 'created_at_asc',
      },
    });
    wrapper = shallowMount(ChatList, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();

    const header = wrapper.getComponent(ChatListHeader);
    const tabs = wrapper.getComponent(ChatTypeTabs);
    expect(header.props('activeStatus')).toBe('open');
    expect(header.props('activeSortBy')).toBe('created_at_asc');

    tabs.vm.$emit('chatTabChange', 'unassigned');
    await flushPromises();

    expect(header.props('activeStatus')).toBe('pending');

    tabs.vm.$emit('chatTabChange', 'all');
    await flushPromises();

    expect(header.props('activeStatus')).toBe('all');
  });

  it('waits for pending preference saves across list remounts', async () => {
    await flushPromises();
    let resolveFirstSave;
    mocks.updateUISettings.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirstSave = resolve;
        })
    );
    wrapper
      .getComponent(ChatListHeader)
      .vm.$emit('basicFilterChange', 'resolved', 'status');
    await flushPromises();

    expect(mocks.updateUISettings).toHaveBeenCalledTimes(1);

    wrapper.unmount();
    wrapper = shallowMount(ChatList, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();

    wrapper
      .getComponent(ChatListHeader)
      .vm.$emit('basicFilterChange', 'last_activity_at_asc', 'sort');
    await flushPromises();

    expect(mocks.updateUISettings).toHaveBeenCalledTimes(1);

    resolveFirstSave();
    await flushPromises();

    expect(mocks.updateUISettings).toHaveBeenCalledTimes(2);
    expect(mocks.updateUISettings.mock.calls[1][0]).toEqual(
      expect.objectContaining({
        conversation_list_filters: expect.objectContaining({
          me: { status: 'resolved', sort_by: 'last_activity_at_asc' },
        }),
      })
    );
  });
});
