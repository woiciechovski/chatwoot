<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  execution: { type: Object, default: null },
  teams: { type: Array, default: () => [] },
  busy: { type: Boolean, default: false },
  contact: { type: Object, default: null },
  inboxName: { type: String, default: '' },
});

const emit = defineEmits(['transfer']);

const teamId = defineModel('teamId', { type: String, default: '' });
</script>

<template>
  <aside
    class="flex w-full flex-col gap-4 border-s border-n-weak bg-n-surface-1 p-4 md:w-72"
  >
    <h2 class="m-0 text-heading-3 text-n-slate-12">
      {{ $t('TRIAGE.TRANSFER_TITLE') }}
    </h2>
    <div
      v-if="contact || inboxName"
      class="flex flex-col gap-2 text-body-main text-n-slate-11"
    >
      <h3 class="m-0 text-label-medium text-n-slate-12">
        {{ contact?.name || $t('TRIAGE.UNKNOWN_CONTACT') }}
      </h3>
      <p v-if="contact?.email" class="m-0">
        <span class="text-label-small">{{ $t('TRIAGE.EMAIL') }}</span>
        {{ contact.email }}
      </p>
      <p v-if="contact?.phone_number" class="m-0">
        <span class="text-label-small">{{ $t('TRIAGE.PHONE') }}</span>
        {{ contact.phone_number }}
      </p>
      <p v-if="inboxName" class="m-0">
        <span class="text-label-small">{{ $t('TRIAGE.INBOX') }}</span>
        {{ inboxName }}
      </p>
    </div>
    <div
      v-if="execution"
      class="flex flex-col gap-1 text-body-main text-n-slate-11"
    >
      <span>
        <strong>{{ $t('TRIAGE.FLOW') }}</strong> {{ execution.flow.name }}
      </span>
      <span>
        <strong>{{ $t('TRIAGE.RESERVED') }}</strong> {{ execution.reserved_at }}
      </span>
      <span v-if="execution.status === 'failed'" class="text-n-ruby-11">
        {{ $t('TRIAGE.TRANSFER_FAILED') }}
      </span>
    </div>
    <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
      {{ $t('TRIAGE.TEAM') }}
      <select
        v-model="teamId"
        class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-body-main text-n-slate-12"
        :disabled="busy"
      >
        <option value="">{{ $t('TRIAGE.SELECT_TEAM') }}</option>
        <option v-for="team in teams" :key="team.id" :value="String(team.id)">
          {{ team.name }}
        </option>
      </select>
    </label>
    <Button
      :label="$t('TRIAGE.TRANSFER')"
      :disabled="!execution || !teamId || busy"
      :is-loading="busy"
      @click="emit('transfer', teamId)"
    />
  </aside>
</template>
