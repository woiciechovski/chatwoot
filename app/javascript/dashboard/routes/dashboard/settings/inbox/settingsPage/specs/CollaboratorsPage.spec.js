import { flushPromises, shallowMount } from '@vue/test-utils';
import CollaboratorsPage from '../CollaboratorsPage.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const { dispatch, alert } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  alert: vi.fn(),
}));

vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({
    dispatch,
    getters: {
      'agents/getAgents': [],
      'accounts/isFeatureEnabledonAccount': () => () => false,
    },
  }),
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false, enterprisePlanName: 'community' }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isOnChatwootCloud: true }),
}));

const mountComponent = inbox =>
  shallowMount(CollaboratorsPage, {
    props: { inbox: { id: 387, agent_conversation_access: 'all', ...inbox } },
    global: {
      stubs: {
        SettingsAccordion: { template: '<section><slot /></section>' },
        'woot-input': true,
        SettingsToggleSection: {
          props: ['modelValue', 'header', 'description'],
          emits: ['update:modelValue'],
          template:
            '<button :data-header="header" @click="$emit(\'update:modelValue\', !modelValue)">{{ header }} {{ description }}</button>',
        },
      },
      mocks: { $t: key => key },
    },
  });

describe('CollaboratorsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    dispatch.mockImplementation(action => {
      if (action === 'inboxMembers/get') {
        return Promise.resolve({ data: { payload: [] } });
      }
      return Promise.resolve();
    });
  });

  it('shows the inbox conversation access restriction disabled by default', async () => {
    const wrapper = mountComponent({});
    await flushPromises();

    const accessToggle = wrapper
      .findAllComponents(SettingsToggleSection)
      .find(component =>
        component.props('header')?.includes('CONVERSATION_ACCESS')
      );

    expect(accessToggle).toBeDefined();
    expect(accessToggle.props('modelValue')).toBe(false);
  });

  it('saves the restricted inbox conversation access mode when enabled', async () => {
    const wrapper = mountComponent({});
    await flushPromises();

    const accessToggle = wrapper
      .findAllComponents(SettingsToggleSection)
      .find(component =>
        component.props('header')?.includes('CONVERSATION_ACCESS')
      );

    accessToggle.vm.$emit('update:modelValue', true);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 387,
      formData: false,
      agent_conversation_access: 'assigned_participating_or_team',
    });
    expect(alert).toHaveBeenCalled();
  });
});
