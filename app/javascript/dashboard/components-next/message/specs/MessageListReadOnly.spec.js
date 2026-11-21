import { defineComponent, h } from 'vue';
import { shallowMount } from '@vue/test-utils';
import MessageList from '../MessageList.vue';

vi.mock('dashboard/composables/store.js', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => ({})) };
});

const MessageStub = defineComponent({
  name: 'Message',
  props: { readOnly: { type: Boolean, default: false } },
  setup(props) {
    return () => h('div', { 'data-read-only': String(props.readOnly) });
  },
});

describe('MessageList read-only state', () => {
  it('passes the read-only state to each message', () => {
    const wrapper = shallowMount(MessageList, {
      props: {
        currentUserId: 1,
        readOnly: true,
        messages: [
          {
            id: 5,
            created_at: 1,
            message_type: 0,
            status: 'sent',
            conversation_id: 8,
          },
        ],
      },
      global: { stubs: { Message: MessageStub, CampaignMessage: true } },
    });

    expect(wrapper.getComponent(MessageStub).attributes('data-read-only')).toBe(
      'true'
    );
  });
});
