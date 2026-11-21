<script setup>
import { computed, onBeforeUnmount, onMounted, provide, ref, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import wootConstants from 'dashboard/constants/globals';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import {
  CONTACT_CONVERSATION_NAVIGATION,
  useContactConversationNavigation,
} from 'dashboard/composables/useContactConversationNavigation';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import triageAPI from 'dashboard/api/triage';
import TriageConversationList from './TriageConversationList.vue';
import TransferPanel from './TransferPanel.vue';

const store = useStore();
const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');
const currentChat = useMapGetter('getSelectedChat');
const conversationById = useMapGetter('getConversationById');
const { run: runListRequest, abort, isPending } = useAbortableRequest();

provide(CONTACT_CONVERSATION_NAVIGATION, useContactConversationNavigation());

const items = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const searchQuery = ref('');
const inboxId = ref('');
const sortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_ASC);
const page = ref(1);
const selectedId = ref(null);
const selectedExecution = ref(null);
const selectedTeamId = ref('');
const isTransferring = ref(false);

const selectedConversationId = computed(() => Number(selectedId.value));
const queueItems = computed(() => items.value);
const selectedInboxName = computed(() => {
  const selectedInbox = inboxes.value.find(
    inbox => String(inbox.id) === String(currentChat.value.inbox_id)
  );
  return selectedInbox?.name || currentChat.value.meta?.channel || '';
});

const clearSelection = () => {
  selectedId.value = null;
  selectedExecution.value = null;
  selectedTeamId.value = '';
  store.dispatch('clearSelectedState');
};

const loadQueue = async () => {
  try {
    const response = await runListRequest(signal =>
      triageAPI.get(
        {
          page: page.value,
          q: searchQuery.value.trim() || undefined,
          inbox_id: inboxId.value || undefined,
          sort_by: sortBy.value,
        },
        { signal }
      )
    );
    if (!response) return;

    const { data } = response.data;
    items.value = data.payload;
    meta.value = data.meta;

    if (selectedId.value) {
      const selected = items.value.find(
        item => Number(item.conversation.id) === selectedConversationId.value
      );
      if (selected) selectedExecution.value = selected.execution;
      else clearSelection();
    }
  } catch {
    useAlert(t('TRIAGE.ERRORS.LOAD'));
  }
};

const selectConversation = async item => {
  selectedId.value = Number(item.conversation.id);
  selectedExecution.value = item.execution;
  selectedTeamId.value = '';
  store.dispatch('clearSelectedState');

  await store.dispatch('getConversation', selectedId.value);
  const conversation = conversationById.value(selectedId.value);
  if (!conversation?.id) {
    useAlert(t('TRIAGE.ERRORS.CONVERSATION'));
    return;
  }
  await store.dispatch('setActiveChat', { data: conversation });
};

const transferConversation = async teamId => {
  if (!selectedId.value || !teamId) return;

  isTransferring.value = true;
  try {
    await triageAPI.transfer(selectedId.value, teamId);
    useAlert(t('TRIAGE.TRANSFER_SUCCESS'));
    clearSelection();
    await loadQueue();
  } catch (error) {
    useAlert(error.response?.data?.error || t('TRIAGE.ERRORS.TRANSFER'));
    await loadQueue();
  } finally {
    isTransferring.value = false;
  }
};

const changePage = nextPage => {
  page.value = nextPage;
  clearSelection();
  loadQueue();
};

const refreshQueue = useDebounceFn(loadQueue, 250);
const filterQueue = useDebounceFn(() => {
  page.value = 1;
  clearSelection();
  loadQueue();
}, 300);

watch([searchQuery, inboxId], filterQueue);
watch(sortBy, () => changePage(1));

onMounted(() => {
  store.dispatch('clearSelectedState');
  store.dispatch('inboxes/get');
  store.dispatch('teams/get');
  loadQueue();
  emitter.on(BUS_EVENTS.TRIAGE_QUEUE_REFRESH, refreshQueue);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, refreshQueue);
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.TRIAGE_QUEUE_REFRESH, refreshQueue);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, refreshQueue);
  abort();
  store.dispatch('clearSelectedState');
});
</script>

<template>
  <main class="flex h-full min-h-0 w-full flex-col md:flex-row">
    <TriageConversationList
      v-model:search-query="searchQuery"
      v-model:inbox-id="inboxId"
      v-model:sort-by="sortBy"
      :items="queueItems"
      :inboxes="inboxes"
      :loading="isPending"
      :page="meta.current_page || page"
      :total-pages="meta.total_pages || 1"
      :selected-id="selectedConversationId"
      @select="selectConversation"
      @page-change="changePage"
    />
    <ConversationBox
      v-if="currentChat.id"
      class="min-h-0 min-w-0 flex-1"
      :is-on-expanded-layout="false"
      read-only
    >
      <div />
    </ConversationBox>
    <div
      v-else
      class="flex min-h-0 min-w-0 flex-1 items-center justify-center text-body-main text-n-slate-10"
    >
      {{ $t('TRIAGE.SELECT_CONVERSATION') }}
    </div>
    <TransferPanel
      v-model:team-id="selectedTeamId"
      :execution="selectedExecution"
      :teams="teams"
      :contact="currentChat.meta?.sender"
      :inbox-name="selectedInboxName"
      :busy="isTransferring"
      @transfer="transferConversation"
    />
  </main>
</template>
