import { shallowMount } from '@vue/test-utils';
import Message from '../Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../constants';

vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: key =>
      computed(() => {
        const getters = {
          'inboxes/getInbox': () => ({}),
          'globalConfig/isOnChatwootCloud': false,
          getAutoTranslate: { language: '' },
          getMessageTranslationState: () => ({ pending: false }),
        };
        return getters[key];
      }),
  };
});
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {} }) }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));
vi.mock('dashboard/composables/useTranslations', async () => {
  const { computed } = await import('vue');
  return {
    useTranslations: () => ({ translationContent: computed(() => '') }),
  };
});

const mountMessage = readOnly =>
  shallowMount(Message, {
    props: {
      id: 1,
      messageType: MESSAGE_TYPES.INCOMING,
      status: MESSAGE_STATUS.SENT,
      conversationId: 1,
      createdAt: Math.floor(Date.now() / 1000),
      currentUserId: 1,
      content: 'Please help',
      readOnly,
    },
  });

describe('Message read-only state', () => {
  it('hides message actions while triage is read-only', () => {
    const wrapper = mountMessage(true);

    expect(wrapper.find('.context-menu-wrap').exists()).toBe(false);
  });

  it('keeps message actions in regular conversations', () => {
    const wrapper = mountMessage(false);

    expect(wrapper.find('.context-menu-wrap').exists()).toBe(true);
  });
});
