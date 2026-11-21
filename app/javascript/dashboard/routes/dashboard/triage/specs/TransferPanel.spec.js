import { mount } from '@vue/test-utils';
import TransferPanel from '../TransferPanel.vue';

describe('TransferPanel', () => {
  it('requires a team and emits the transfer request', async () => {
    const wrapper = mount(TransferPanel, {
      props: {
        execution: { flow: { name: 'Returns' } },
        teams: [{ id: 7, name: 'Support' }],
        contact: {
          name: 'Taylor',
          email: 'taylor@example.com',
          phone_number: '+1 555 0100',
        },
        inboxName: 'WhatsApp',
      },
      global: {
        mocks: { $t: key => key },
        stubs: {
          Button: {
            props: ['label', 'disabled', 'isLoading'],
            emits: ['click'],
            template:
              '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
          },
        },
      },
    });

    const transferButton = wrapper.find('button');
    expect(wrapper.text()).toContain('Taylor');
    expect(wrapper.text()).toContain('taylor@example.com');
    expect(wrapper.text()).toContain('+1 555 0100');
    expect(wrapper.text()).toContain('WhatsApp');
    expect(transferButton.element.disabled).toBe(true);
    await wrapper.find('select').setValue('7');
    expect(transferButton.element.disabled).toBe(false);
    await transferButton.trigger('click');

    expect(wrapper.emitted('transfer')[0]).toEqual(['7']);
  });
});
