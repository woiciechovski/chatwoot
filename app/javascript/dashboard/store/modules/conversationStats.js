import types from '../mutation-types';
import ConversationApi from '../../api/inbox/conversation';
import { debounce } from '@chatwoot/utils';

const state = {
  mineCount: 0,
  unAssignedCount: 0,
  allCount: 0,
  statusCounts: null,
};

// Tabs can share a response when they use the same status and view scope.
const getViewKey = ({
  inboxId,
  status,
  labels,
  teamId,
  conversationType,
  queryData,
  tabStatuses,
}) =>
  JSON.stringify([
    ConversationApi.url,
    queryData || {
      inboxId,
      status: tabStatuses ? undefined : status,
      countsByStatus: Boolean(tabStatuses),
      labels,
      teamId,
      conversationType,
    },
  ]);

export const getters = {
  getStats: $state => $state,
  getCountsByStatus: $state => params =>
    $state.statusCounts?.key === getViewKey(params)
      ? $state.statusCounts.counts
      : {},
};

const makeView = (key = null, params = {}) => ({
  key,
  params,
  committedRequestIds: new Map(),
  requestedStatuses: new Set(),
});

let activeView = makeView();
let requestId = 0;

const isCurrentRequest = request =>
  request.view === activeView &&
  request.id >= (request.view.committedRequestIds.get(request.status) ?? 0);

const commitCounts = (commit, meta, request) => {
  if (!isCurrentRequest(request)) return false;

  const { id, status, view } = request;
  view.committedRequestIds.set(status, id);
  if (status) {
    view.requestedStatuses.add(status);
    commit(types.SET_CONV_TAB_STATUS_META, { key: view.key, status, meta });
  } else {
    commit(types.SET_CONV_TAB_META, meta);
  }
  return true;
};

const fetchMetaData = async (commit, params, request) => {
  if (!isCurrentRequest(request)) return;

  try {
    const response = params.queryData
      ? await ConversationApi.filter({ queryData: params.queryData, page: 1 })
      : await ConversationApi.meta(params);
    const {
      data: { meta },
    } = response;
    commitCounts(commit, meta, request);
  } catch (error) {
    // ignore
  }
};

const refreshViewCounts = (commit, request) => {
  if (request.view !== activeView) return;

  const { params } = request.view;
  if (params.tabStatuses) {
    params.tabStatuses.forEach(status => {
      fetchMetaData(commit, { ...params, status }, { ...request, status });
    });
  } else {
    fetchMetaData(commit, params, request);
  }
};

const debouncedFetchMetaData = debounce(refreshViewCounts, 1000, false, 5000);
const longDebouncedFetchMetaData = debounce(
  refreshViewCounts,
  7500,
  false,
  20000
);
const superLongDebouncedFetchMetaData = debounce(
  refreshViewCounts,
  15000,
  false,
  30000
);

const metaDebouncers = {
  default: debouncedFetchMetaData,
  long: longDebouncedFetchMetaData,
  superLong: superLongDebouncedFetchMetaData,
};

// allCount is 0 until a meta request succeeds; under load it stays 0, so treat
// the unknown case as a large account and poll slowest instead of fastest.
export const getMetaDebounceKey = allCount => {
  if (allCount > 2000 || allCount === 0) return 'superLong';
  if (allCount > 100) return 'long';
  return 'default';
};

const countForDebounce = ($state, params) => {
  if (!params.tabStatuses) return $state.allCount;

  const counts = getters.getCountsByStatus($state)(params);
  if (params.tabStatuses.some(status => !counts[status])) return 0;
  return Math.max(...params.tabStatuses.map(status => counts[status].allCount));
};

export const actions = {
  get: ({ commit, state: $state }, params = activeView.params) => {
    if (getViewKey(params) !== activeView.key) return;

    requestId += 1;
    const debounceKey = getMetaDebounceKey(
      countForDebounce($state, activeView.params)
    );
    metaDebouncers[debounceKey](commit, {
      view: activeView,
      id: requestId,
    });
  },
  onListRequestStarted(_, params) {
    const key = getViewKey(params);
    if (key !== activeView.key) {
      activeView = makeView(key, params);
    }
    activeView.params = params;
    requestId += 1;
    return {
      view: activeView,
      id: requestId,
      status: params.tabStatuses ? params.status : undefined,
    };
  },
  set({ commit }, { meta, request }) {
    if (!commitCounts(commit, meta, request)) return;

    // Reuse the list response for its status and load each other status once.
    const { view } = request;
    view.params.tabStatuses?.forEach(status => {
      if (view.requestedStatuses.has(status)) return;

      view.requestedStatuses.add(status);
      requestId += 1;
      fetchMetaData(
        commit,
        { ...view.params, status },
        { view, id: requestId, status }
      );
    });
  },
};

const readCounts = ({
  mine_count: mineCount,
  unassigned_count: unAssignedCount,
  all_count: allCount,
} = {}) => ({ mineCount, unAssignedCount, allCount });

export const mutations = {
  [types.SET_CONV_TAB_META]($state, meta) {
    Object.assign($state, readCounts(meta), { updatedOn: new Date() });
  },
  [types.SET_CONV_TAB_STATUS_META]($state, { key, status, meta }) {
    if ($state.statusCounts?.key !== key) {
      $state.statusCounts = { key, counts: {} };
    }
    $state.statusCounts.counts[status] = readCounts(meta);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
