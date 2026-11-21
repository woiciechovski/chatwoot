import { computed, defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import MessageError from '../MessageError.vue';
import { provideMessageContext } from '../provider.js';
import { MESSAGE_STATUS, ORIENTATION } from '../constants';

vi.mock('dashboard/composables/store', async () => {
  const { computed: makeComputed } = await import('vue');
  return { useMapGetter: () => makeComputed(() => []) };
});
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const mountMessageError = readOnly => {
  const Host = defineComponent({
    setup() {
      provideMessageContext({
        orientation: computed(() => ORIENTATION.LEFT),
        status: ref(MESSAGE_STATUS.FAILED),
        createdAt: ref(Math.floor(Date.now() / 1000)),
        content: ref('Please help'),
        attachments: ref([]),
      });

      return () => h(MessageError, { error: 'Temporary error', readOnly });
    },
  });

  return mount(Host, { global: { stubs: { Icon: true } } });
};

describe('MessageError read-only state', () => {
  it('hides retry actions in read-only conversations', () => {
    const wrapper = mountMessageError(true);

    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.text()).toContain('Temporary error');
  });

  it('allows retry actions in regular conversations', () => {
    const wrapper = mountMessageError(false);

    expect(wrapper.find('button').exists()).toBe(true);
  });
});
