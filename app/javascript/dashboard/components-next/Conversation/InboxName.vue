<script setup>
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';

defineProps({
  inbox: {
    type: Object,
    default: () => {},
  },
  label: { type: String, default: '' },
});
</script>

<template>
  <div :title="label || inbox.name" class="flex items-center gap-0.5 min-w-0">
    <ChannelIcon
      v-if="inbox.name"
      :inbox="inbox"
      class="size-4 flex-shrink-0 text-n-slate-11"
    />
    <span class="truncate text-body-main text-n-slate-11">
      {{ label || inbox.name }}
    </span>
  </div>
</template>
