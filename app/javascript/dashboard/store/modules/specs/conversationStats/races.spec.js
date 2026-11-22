import axios from 'axios';
import { actions, getters, mutations } from '../../conversationStats';
import conversationActions from '../../conversations/actions';

vi.mock('axios');
global.axios = axios;

describe('conversation count refresh races', () => {
  let state;
  let commit;
  let listContext;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(0);
    state = { allCount: 30 };
    actions.onListRequestStarted({}, { status: 'open' });
    commit = (type, payload) => mutations[type](state, payload);
    listContext = {
      commit: vi.fn(),
      dispatch: vi.fn((type, payload) => {
        if (type.startsWith('conversationStats/')) {
          return actions[type.split('/')[1]]({ commit, state }, payload);
        }
        return undefined;
      }),
      state: { conversationFilters: { status: 'open', page: 1 } },
    };
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('does not send a queued open-count request after filtered counts arrive', async () => {
    axios.get.mockResolvedValue({ data: { meta: { all_count: 30 } } });
    actions.get({ commit, state }, { status: 'open' });
    expect(axios.get).not.toHaveBeenCalled();

    axios.post.mockResolvedValue({
      data: { payload: [], meta: { all_count: 10757 } },
    });
    await conversationActions.fetchFilteredConversations(listContext, {
      queryData: {
        payload: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['all'],
          },
        ],
      },
      page: 1,
    });
    await vi.runAllTimersAsync();

    expect(axios.get).not.toHaveBeenCalled();
    expect(state.allCount).toBe(10757);
  });

  it('ignores an in-flight open-count response after filtered counts arrive', async () => {
    let resolveResponse;
    axios.get.mockReturnValue(
      new Promise(resolve => {
        resolveResponse = resolve;
      })
    );
    actions.get({ commit, state }, { status: 'open' });
    await vi.runAllTimersAsync();
    expect(axios.get).toHaveBeenCalledOnce();

    axios.post.mockResolvedValue({
      data: { payload: [], meta: { all_count: 10757 } },
    });
    await conversationActions.fetchFilteredConversations(listContext, {
      queryData: {
        payload: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['all'],
          },
        ],
      },
      page: 1,
    });
    resolveResponse({ data: { meta: { all_count: 30 } } });
    await vi.runAllTimersAsync();

    expect(state.allCount).toBe(10757);
  });

  it('continues refreshing counts after a list response', async () => {
    const request = actions.onListRequestStarted({}, { status: 'open' });
    actions.set({ commit }, { meta: { all_count: 30 }, request });
    axios.get.mockResolvedValue({ data: { meta: { all_count: 31 } } });
    actions.get({ commit, state }, { status: 'open' });
    await vi.runAllTimersAsync();

    expect(state.allCount).toBe(31);
  });

  it.each([1, 2])(
    'preserves an event refresh queued while list page %s is in flight',
    async page => {
      let resolveList;
      axios.get.mockReturnValueOnce(
        new Promise(resolve => {
          resolveList = resolve;
        })
      );
      listContext.state.conversationFilters.page = page;
      const listRequest =
        conversationActions.fetchAllConversations(listContext);

      axios.get.mockResolvedValue({ data: { meta: { all_count: 31 } } });
      actions.get({ commit, state }, { status: 'open' });
      resolveList({ data: { data: { payload: [], meta: { all_count: 30 } } } });
      await listRequest;
      await vi.runAllTimersAsync();

      expect(axios.get).toHaveBeenCalledTimes(2);
      expect(state.allCount).toBe(31);
    }
  );

  it('keeps a newer event count when the older list response arrives last', async () => {
    let resolveList;
    axios.get.mockReturnValueOnce(
      new Promise(resolve => {
        resolveList = resolve;
      })
    );
    const listRequest = conversationActions.fetchAllConversations(listContext);

    axios.get.mockResolvedValue({ data: { meta: { all_count: 31 } } });
    actions.get({ commit, state }, { status: 'open' });
    await vi.runAllTimersAsync();
    expect(state.allCount).toBe(31);

    resolveList({ data: { data: { payload: [], meta: { all_count: 30 } } } });
    await listRequest;

    expect(state.allCount).toBe(31);
  });

  it('retains a queued event refresh when a same-view list request fails', async () => {
    actions.get({ commit, state }, { status: 'open' });
    axios.get.mockRejectedValueOnce(new Error('List failed'));
    await conversationActions.fetchAllConversations(listContext);

    axios.get.mockResolvedValue({ data: { meta: { all_count: 31 } } });
    await vi.runAllTimersAsync();

    expect(state.allCount).toBe(31);
  });

  it('retains an in-flight event refresh when a same-view list request fails', async () => {
    let resolveMeta;
    axios.get.mockReturnValueOnce(
      new Promise(resolve => {
        resolveMeta = resolve;
      })
    );
    actions.get({ commit, state }, { status: 'open' });
    await vi.runAllTimersAsync();

    axios.get.mockRejectedValueOnce(new Error('List failed'));
    await conversationActions.fetchAllConversations(listContext);
    resolveMeta({ data: { meta: { all_count: 31 } } });
    await vi.runAllTimersAsync();

    expect(state.allCount).toBe(31);
  });

  it('discards old-view refreshes even when the new filter request fails', async () => {
    actions.get({ commit, state }, { status: 'open' });
    axios.post.mockRejectedValue(new Error('Filter failed'));
    await expect(
      conversationActions.fetchFilteredConversations(listContext, {
        queryData: {
          payload: [
            {
              attribute_key: 'status',
              filter_operator: 'equal_to',
              values: ['all'],
            },
          ],
        },
        page: 1,
      })
    ).rejects.toThrow('Filter failed');
    await vi.runAllTimersAsync();

    expect(axios.get).not.toHaveBeenCalled();
    expect(state.allCount).toBe(30);
  });

  it('discards older queued metadata after a successful same-view list refresh', async () => {
    actions.get({ commit, state }, { status: 'open' });
    axios.get.mockResolvedValueOnce({
      data: { data: { payload: [], meta: { all_count: 31 } } },
    });
    await conversationActions.fetchAllConversations(listContext);
    await vi.runAllTimersAsync();

    expect(axios.get).toHaveBeenCalledOnce();
    expect(state.allCount).toBe(31);
  });

  it('does not let a failed newer metadata request block a successful list response', async () => {
    let resolveList;
    axios.get.mockReturnValueOnce(
      new Promise(resolve => {
        resolveList = resolve;
      })
    );
    const listRequest = conversationActions.fetchAllConversations(listContext);

    axios.get.mockRejectedValue(new Error('Metadata failed'));
    actions.get({ commit, state }, { status: 'open' });
    await vi.runAllTimersAsync();
    resolveList({ data: { data: { payload: [], meta: { all_count: 31 } } } });
    await listRequest;

    expect(axios.get).toHaveBeenCalledTimes(2);
    expect(state.allCount).toBe(31);
  });

  it('continues updating shared counts after a cached assignee-tab switch', async () => {
    actions.onListRequestStarted({}, { status: 'open', assigneeType: 'me' });
    axios.get.mockResolvedValue({ data: { meta: { all_count: 31 } } });
    actions.get({ commit, state }, { status: 'open', assigneeType: 'all' });
    await vi.runAllTimersAsync();

    expect(axios.get).toHaveBeenCalledOnce();
    expect(state.allCount).toBe(31);
  });

  it('uses the whole list response only for tabs filtering by all statuses', async () => {
    const filters = {
      inboxId: 2,
      status: 'open',
      tabStatuses: ['open', 'pending', 'all'],
    };
    axios.get.mockImplementation((url, { params }) => {
      const counts = {
        open: { mine_count: 4, unassigned_count: 2, all_count: 6 },
        pending: { mine_count: 1, unassigned_count: 3, all_count: 4 },
        all: { mine_count: 10, unassigned_count: 6, all_count: 16 },
      };
      return Promise.resolve({ data: { meta: counts[params.status] } });
    });

    const mineRequest = actions.onListRequestStarted({ state }, filters);
    actions.set(
      { commit, state },
      {
        meta: { mine_count: 4, unassigned_count: 2, all_count: 6 },
        request: mineRequest,
      }
    );
    await vi.runAllTimersAsync();
    const allRequest = actions.onListRequestStarted(
      { state },
      { ...filters, status: 'all' }
    );
    actions.set(
      { commit, state },
      {
        meta: { mine_count: 10, unassigned_count: 6, all_count: 16 },
        request: allRequest,
      }
    );

    const stats = getters.getCountsByStatus(state)(filters);
    expect(stats.open.mineCount).toBe(4);
    expect(stats.pending.unAssignedCount).toBe(3);
    expect(stats.all.allCount).toBe(16);
    expect(axios.get.mock.calls.map(([, { params }]) => params.status)).toEqual(
      ['pending', 'all']
    );
  });

  it('refreshes each displayed status after an event on a cached tab', async () => {
    const filters = {
      status: 'open',
      tabStatuses: ['open', 'pending'],
    };
    axios.get.mockResolvedValueOnce({
      data: { meta: { unassigned_count: 3, all_count: 4 } },
    });
    const request = actions.onListRequestStarted({}, filters);
    actions.set(
      { commit, state },
      { meta: { mine_count: 4, all_count: 6 }, request }
    );
    await vi.runAllTimersAsync();
    axios.get.mockClear();

    axios.get
      .mockResolvedValueOnce({
        data: { meta: { mine_count: 5, all_count: 7 } },
      })
      .mockResolvedValueOnce({
        data: { meta: { unassigned_count: 2, all_count: 3 } },
      });
    // Switching to a cached tab does not start a list request.
    actions.get({ commit, state }, { ...filters, status: 'pending' });
    await vi.runAllTimersAsync();

    expect(axios.get).toHaveBeenCalledTimes(2);
    const stats = getters.getCountsByStatus(state)(filters);
    expect(stats.open.mineCount).toBe(5);
    expect(stats.pending.unAssignedCount).toBe(2);
  });

  it('ignores metadata from a previous inbox after switching scopes', async () => {
    const filters = {
      inboxId: 1,
      status: 'open',
      tabStatuses: ['open', 'all'],
    };
    let resolveOldMeta;
    axios.get.mockReturnValueOnce(
      new Promise(resolve => {
        resolveOldMeta = resolve;
      })
    );
    const oldRequest = actions.onListRequestStarted({}, filters);
    actions.set(
      { commit, state },
      { meta: { mine_count: 4, all_count: 6 }, request: oldRequest }
    );

    const newFilters = { ...filters, inboxId: 2 };
    expect(getters.getCountsByStatus(state)(newFilters)).toEqual({});
    axios.get.mockResolvedValueOnce({ data: { meta: { all_count: 8 } } });
    const newRequest = actions.onListRequestStarted({}, newFilters);
    actions.set(
      { commit, state },
      { meta: { mine_count: 2, all_count: 3 }, request: newRequest }
    );
    await vi.runAllTimersAsync();

    resolveOldMeta({ data: { meta: { all_count: 16 } } });
    await vi.runAllTimersAsync();

    expect(getters.getCountsByStatus(state)(newFilters).all.allCount).toBe(8);
    expect(getters.getCountsByStatus(state)(filters)).toEqual({});
  });

  it.each([
    [
      'advanced filter',
      {
        payload: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['all'],
          },
        ],
      },
    ],
    [
      'saved folder',
      {
        payload: [
          {
            attribute_key: 'labels',
            filter_operator: 'equal_to',
            values: ['support'],
          },
        ],
      },
    ],
  ])(
    'refreshes the %s total after deleting a conversation',
    async (_, queryData) => {
      axios.post.mockResolvedValueOnce({
        data: { payload: [], meta: { all_count: 30 } },
      });
      await conversationActions.fetchFilteredConversations(listContext, {
        queryData,
        page: 2,
      });
      listContext.commit.mockClear();
      axios.post.mockClear();

      axios.delete.mockResolvedValue({});
      axios.post.mockResolvedValueOnce({
        data: { payload: [], meta: { all_count: 29 } },
      });
      await conversationActions.deleteConversation(listContext, 123);
      await vi.runAllTimersAsync();

      expect(axios.post).toHaveBeenCalledOnce();
      expect(axios.post).toHaveBeenCalledWith(
        expect.stringContaining('/conversations/filter'),
        queryData,
        expect.objectContaining({ params: { page: 1 } })
      );
      expect(axios.get).not.toHaveBeenCalled();
      expect(state.allCount).toBe(29);
      expect(listContext.commit.mock.calls).toEqual([
        ['DELETE_CONVERSATION', 123],
      ]);
    }
  );

  it('continues using metadata to refresh a basic view after deletion', async () => {
    axios.delete.mockResolvedValue({});
    axios.get.mockResolvedValue({ data: { meta: { all_count: 29 } } });
    await conversationActions.deleteConversation(listContext, 123);
    await vi.runAllTimersAsync();

    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('/conversations/meta'),
      expect.objectContaining({
        params: expect.objectContaining({ status: 'open' }),
      })
    );
    expect(axios.post).not.toHaveBeenCalled();
    expect(state.allCount).toBe(29);
  });
});
