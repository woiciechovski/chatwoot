import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import ContactMoreActions from './ContactMoreActions.vue';

const { checkContactPermission, checkContactPermissions } = vi.hoisted(() => ({
  checkContactPermission: vi.fn(),
  checkContactPermissions: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkContactPermission, checkContactPermissions }),
}));

vi.mock('dashboard/components-next/button/Button.vue', () => ({
  default: {
    name: 'Button',
    emits: ['click'],
    template:
      '<button class="actions-button" @click="$emit(&quot;click&quot;)"></button>',
  },
}));

vi.mock('dashboard/components-next/dropdown-menu/DropdownMenu.vue', () => ({
  default: {
    name: 'DropdownMenu',
    props: { menuItems: { type: Array, default: () => [] } },
    template:
      '<div class="menu-items"><span v-for="item in menuItems" :key="item.action">{{ item.action }}</span></div>',
  },
}));

describe('ContactMoreActions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    checkContactPermission.mockImplementation(
      permission => permission !== 'contacts.delete'
    );
    checkContactPermissions.mockReturnValue(false);
  });

  it('hides export when contacts.read is absent even if the export grant is present', async () => {
    const wrapper = mount(ContactMoreActions, {
      global: {
        directives: { onClickaway: {} },
      },
    });

    await wrapper.get('.actions-button').trigger('click');
    await flushPromises();

    expect(checkContactPermissions).toHaveBeenCalledWith([
      'contacts.read',
      'contacts.export',
    ]);
    expect(wrapper.get('.menu-items').text()).toContain('add');
    expect(wrapper.get('.menu-items').text()).not.toContain('export');
  });

  it('shows export when both contacts.read and contacts.export are granted', async () => {
    checkContactPermissions.mockReturnValue(true);
    const wrapper = mount(ContactMoreActions, {
      global: {
        directives: { onClickaway: {} },
      },
    });

    await wrapper.get('.actions-button').trigger('click');
    await flushPromises();

    expect(wrapper.get('.menu-items').text()).toContain('export');
  });
});
