<script setup>
import { computed, onActivated, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import conversationFlowsAPI from 'dashboard/api/conversationFlows';

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const flows = ref([]);
const loading = ref(false);
const saving = ref(false);
const isEditing = ref(false);
const selectedFlowId = ref(null);
const searchQuery = ref('');
let isFirstActivation = true;

const emptyForm = () => ({
  name: '',
  description: '',
  enabled: false,
  inbox_ids: [],
});

const form = reactive(emptyForm());

const filteredFlows = computed(() => {
  const query = searchQuery.value.trim().toLocaleLowerCase();
  if (!query) return flows.value;
  return flows.value.filter(flow =>
    `${flow.name} ${flow.description || ''}`.toLocaleLowerCase().includes(query)
  );
});

const loadFlows = async () => {
  loading.value = true;
  try {
    const { data } = await conversationFlowsAPI.get();
    flows.value = data.payload;
  } catch {
    useAlert(t('CONVERSATION_FLOWS.ERRORS.LOAD'));
  } finally {
    loading.value = false;
  }
};

const openCreateForm = () => {
  Object.assign(form, emptyForm());
  selectedFlowId.value = null;
  isEditing.value = true;
};

const openEditForm = flow => {
  Object.assign(form, {
    name: flow.name,
    description: flow.description || '',
    enabled: flow.enabled,
    inbox_ids: flow.inboxes.map(inbox => inbox.id),
  });
  selectedFlowId.value = flow.id;
  isEditing.value = true;
};

const closeForm = () => {
  isEditing.value = false;
  selectedFlowId.value = null;
};

const saveFlow = async () => {
  saving.value = true;
  const payload = {
    conversation_flow: {
      name: form.name.trim(),
      description: form.description.trim(),
      enabled: form.enabled,
      inbox_ids: form.inbox_ids,
    },
  };

  try {
    if (selectedFlowId.value) {
      await conversationFlowsAPI.update(selectedFlowId.value, payload);
      useAlert(t('CONVERSATION_FLOWS.SAVED'));
    } else {
      await conversationFlowsAPI.create(payload);
      useAlert(t('CONVERSATION_FLOWS.CREATED'));
    }
    closeForm();
    await loadFlows();
  } catch (error) {
    const message = error.response?.data?.error;
    useAlert(message || t('CONVERSATION_FLOWS.ERRORS.SAVE'));
  } finally {
    saving.value = false;
  }
};

const toggleInbox = inboxId => {
  const inboxIds = new Set(form.inbox_ids);
  if (inboxIds.has(inboxId)) inboxIds.delete(inboxId);
  else inboxIds.add(inboxId);
  form.inbox_ids = [...inboxIds];
};

onMounted(() => {
  store.dispatch('inboxes/get');
  loadFlows();
});

onActivated(() => {
  if (isFirstActivation) {
    isFirstActivation = false;
    return;
  }
  loadFlows();
});
</script>

<template>
  <SettingsLayout
    :is-loading="loading && !flows.length"
    :no-records-found="!loading && !flows.length && !isEditing"
    :no-records-message="$t('CONVERSATION_FLOWS.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('CONVERSATION_FLOWS.TITLE')"
        :description="$t('CONVERSATION_FLOWS.DESCRIPTION')"
        :search-placeholder="$t('CONVERSATION_FLOWS.SEARCH')"
      >
        <template #actions>
          <Button
            :label="$t('CONVERSATION_FLOWS.NEW')"
            size="sm"
            @click="openCreateForm"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <form
        v-if="isEditing"
        class="flex flex-col gap-4 rounded-xl border border-n-weak p-4 mb-6"
        @submit.prevent="saveFlow"
      >
        <h2 class="text-heading-2 text-n-slate-12">
          {{
            selectedFlowId
              ? $t('CONVERSATION_FLOWS.EDIT')
              : $t('CONVERSATION_FLOWS.NEW')
          }}
        </h2>
        <label class="flex flex-col gap-1 text-body-main text-n-slate-12">
          {{ $t('CONVERSATION_FLOWS.FORM.NAME') }}
          <input
            v-model="form.name"
            required
            maxlength="120"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2"
            data-testid="flow-name"
          />
        </label>
        <label class="flex flex-col gap-1 text-body-main text-n-slate-12">
          {{ $t('CONVERSATION_FLOWS.FORM.DESCRIPTION') }}
          <textarea
            v-model="form.description"
            rows="3"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2"
          />
        </label>
        <fieldset class="flex flex-col gap-2">
          <legend class="text-body-main font-medium text-n-slate-12">
            {{ $t('CONVERSATION_FLOWS.FORM.INBOXES') }}
          </legend>
          <label
            v-for="inbox in inboxes"
            :key="inbox.id"
            class="flex items-center gap-2 text-body-main text-n-slate-12"
          >
            <input
              type="checkbox"
              :checked="form.inbox_ids.includes(inbox.id)"
              @change="toggleInbox(inbox.id)"
            />
            {{ inbox.name }}
          </label>
        </fieldset>
        <label class="flex items-center gap-2 text-body-main text-n-slate-12">
          <input v-model="form.enabled" type="checkbox" />
          {{ $t('CONVERSATION_FLOWS.FORM.ENABLED') }}
        </label>
        <div class="flex justify-end gap-2">
          <Button
            :label="$t('CONVERSATION_FLOWS.CANCEL')"
            slate
            size="sm"
            type="button"
            @click="closeForm"
          />
          <Button
            :label="$t('CONVERSATION_FLOWS.SAVE')"
            size="sm"
            type="submit"
            :is-loading="saving"
            :disabled="saving || !form.name.trim()"
          />
        </div>
      </form>

      <p
        v-if="!filteredFlows.length && searchQuery"
        class="py-10 text-center text-body-main text-n-slate-11"
      >
        {{ $t('CONVERSATION_FLOWS.NO_RESULTS') }}
      </p>
      <div v-else class="divide-y divide-n-weak border-t border-n-weak">
        <article
          v-for="flow in filteredFlows"
          :key="flow.id"
          class="flex flex-wrap items-center justify-between gap-4 py-4"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <h3 class="m-0 text-heading-3 text-n-slate-12">
                {{ flow.name }}
              </h3>
              <span
                class="rounded-full px-2 py-0.5 text-label-small"
                :class="
                  flow.enabled
                    ? 'bg-n-teal-2 text-n-teal-11'
                    : 'bg-n-slate-3 text-n-slate-11'
                "
              >
                {{
                  flow.enabled
                    ? $t('CONVERSATION_FLOWS.STATUS.ENABLED')
                    : $t('CONVERSATION_FLOWS.STATUS.DISABLED')
                }}
              </span>
            </div>
            <p class="mb-1 mt-1 text-body-main text-n-slate-11">
              {{ flow.description || $t('CONVERSATION_FLOWS.NO_DESCRIPTION') }}
            </p>
            <p class="m-0 text-label-small text-n-slate-10">
              {{
                flow.inboxes.map(inbox => inbox.name).join(', ') ||
                $t('CONVERSATION_FLOWS.NO_INBOXES')
              }}
            </p>
          </div>
          <Button
            :label="$t('CONVERSATION_FLOWS.EDIT')"
            slate
            size="sm"
            @click="openEditForm(flow)"
          />
        </article>
      </div>
    </template>
  </SettingsLayout>
</template>
