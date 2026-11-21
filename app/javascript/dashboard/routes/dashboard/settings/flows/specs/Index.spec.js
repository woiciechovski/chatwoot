import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import FlowIndex from '../Index.vue';
import conversationFlowsAPI from 'dashboard/api/conversationFlows';

const inboxes = ref([{ id: 4, name: 'Support' }]);
const dispatch = vi.fn();
const flow = {
  id: 8,
  name: 'Existing flow',
  description: 'Priority contacts',
  enabled: true,
  inboxes: [{ id: 4, name: 'Support' }],
};

vi.mock('dashboard/api/conversationFlows', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => inboxes,
  useStore: () => ({ dispatch }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const mountComponent = () =>
  mount(FlowIndex, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: {
          template: '<header><slot name="actions" /></header>',
        },
        Button: {
          props: ['label', 'type', 'disabled', 'isLoading'],
          emits: ['click'],
          template:
            '<button :type="type || \'button\'" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('Conversation flow settings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    conversationFlowsAPI.get.mockResolvedValue({ data: { payload: [] } });
  });

  it('creates a flow with selected inboxes and activation state', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CONVERSATION_FLOWS.NEW')
      .trigger('click');
    await wrapper.find('[data-testid="flow-name"]').setValue('Returns');
    await wrapper.find('fieldset input[type="checkbox"]').setValue(true);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(conversationFlowsAPI.create).toHaveBeenCalledWith({
      conversation_flow: {
        name: 'Returns',
        description: '',
        enabled: false,
        inbox_ids: [4],
      },
    });
  });

  it('edits an existing flow and preserves its inbox mapping', async () => {
    conversationFlowsAPI.get.mockResolvedValue({ data: { payload: [flow] } });
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CONVERSATION_FLOWS.EDIT')
      .trigger('click');
    await wrapper.find('[data-testid="flow-name"]').setValue('Updated flow');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(conversationFlowsAPI.update).toHaveBeenCalledWith(8, {
      conversation_flow: {
        name: 'Updated flow',
        description: 'Priority contacts',
        enabled: true,
        inbox_ids: [4],
      },
    });
  });
});
