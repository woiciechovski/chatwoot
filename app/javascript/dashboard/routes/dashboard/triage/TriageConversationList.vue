<script setup>
import { computed } from 'vue';
import format from 'date-fns/format';
import fromUnixTime from 'date-fns/fromUnixTime';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConversationBasicFilter from 'dashboard/components/widgets/conversation/ConversationBasicFilter.vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  page: { type: Number, default: 1 },
  totalPages: { type: Number, default: 1 },
  selectedId: { type: Number, default: null },
});

const emit = defineEmits([
  'select',
  'update:searchQuery',
  'update:inboxId',
  'pageChange',
]);

const searchQuery = defineModel('searchQuery', { type: String, default: '' });
const inboxId = defineModel('inboxId', { type: String, default: '' });
const sortBy = defineModel('sortBy', { type: String, required: true });

const hasItems = computed(() => props.items.length > 0);

const inboxName = conversation => {
  const inbox = props.inboxes.find(
    item => String(item.id) === String(conversation.inbox_id)
  );
  return inbox?.name || conversation.meta?.channel || '';
};

const lastMessageTime = conversation => {
  const timestamp = Number(conversation.messages?.[0]?.created_at);
  if (!timestamp) return null;

  const date = fromUnixTime(timestamp);
  return {
    datetime: date.toISOString(),
    label: format(date, 'dd MMM yyyy, h:mm a'),
  };
};
</script>

<template>
  <aside
    class="flex w-full flex-col border-e border-n-weak bg-n-surface-1 md:w-80"
  >
    <header class="flex flex-col gap-3 border-b border-n-weak p-4">
      <div class="flex items-center justify-between gap-2">
        <h1 class="m-0 text-heading-2 text-n-slate-12">
          {{ $t('TRIAGE.TITLE') }}
        </h1>
        <ConversationBasicFilter
          v-model:sort-by="sortBy"
          is-on-expanded-layout
          :show-status-filter="false"
        />
      </div>
      <Input
        v-model="searchQuery"
        :placeholder="$t('TRIAGE.SEARCH')"
        type="search"
      />
      <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
        {{ $t('TRIAGE.INBOX_FILTER') }}
        <select
          v-model="inboxId"
          class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-body-main text-n-slate-12"
        >
          <option value="">{{ $t('TRIAGE.ALL_INBOXES') }}</option>
          <option
            v-for="inbox in inboxes"
            :key="inbox.id"
            :value="String(inbox.id)"
          >
            {{ inbox.name }}
          </option>
        </select>
      </label>
    </header>

    <div class="min-h-0 flex-1 overflow-y-auto">
      <p
        v-if="!loading && !hasItems"
        class="px-4 py-10 text-center text-body-main text-n-slate-11"
      >
        {{ $t('TRIAGE.EMPTY') }}
      </p>
      <button
        v-for="item in items"
        :key="item.execution.id"
        type="button"
        class="flex w-full flex-col gap-1 border-b border-n-weak px-4 py-3 text-start hover:bg-n-alpha-2"
        :class="item.conversation.id === selectedId ? 'bg-n-brand/10' : ''"
        :aria-pressed="item.conversation.id === selectedId"
        @click="emit('select', item)"
      >
        <span class="flex items-center justify-between gap-2">
          <strong class="truncate text-body-main text-n-slate-12">
            {{
              item.conversation.meta?.sender?.name ||
              $t('TRIAGE.UNKNOWN_CONTACT')
            }}
          </strong>
          <span class="shrink-0 text-label-small text-n-slate-10">
            {{ $t('TRIAGE.CONVERSATION_NUMBER', { id: item.conversation.id }) }}
          </span>
        </span>
        <span class="truncate text-label-small text-n-slate-11">
          {{
            item.conversation.messages?.[0]?.content || $t('TRIAGE.NO_MESSAGE')
          }}
        </span>
        <span class="truncate text-label-small text-n-slate-10">
          {{ item.execution.flow.name }}
        </span>
        <span class="truncate text-label-small text-n-slate-10">
          {{ inboxName(item.conversation) }}
        </span>
        <time
          v-if="lastMessageTime(item.conversation)"
          class="text-label-small text-n-slate-10"
          :datetime="lastMessageTime(item.conversation).datetime"
        >
          {{ lastMessageTime(item.conversation).label }}
        </time>
      </button>
    </div>

    <footer
      class="flex items-center justify-between border-t border-n-weak p-3"
    >
      <Button
        :label="$t('TRIAGE.PREVIOUS')"
        slate
        sm
        :disabled="loading || page <= 1"
        @click="emit('pageChange', page - 1)"
      />
      <span class="text-label-small text-n-slate-11">
        {{ $t('TRIAGE.PAGE', { page, totalPages }) }}
      </span>
      <Button
        :label="$t('TRIAGE.NEXT')"
        slate
        sm
        :disabled="loading || page >= totalPages"
        @click="emit('pageChange', page + 1)"
      />
    </footer>
  </aside>
</template>
