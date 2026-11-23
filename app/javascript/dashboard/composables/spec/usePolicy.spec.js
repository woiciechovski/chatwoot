import { computed, defineComponent, h, ref } from 'vue';
import { createStore } from 'vuex';
import { flushPromises, mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import { usePolicy } from '../usePolicy';

const { getCapabilities } = vi.hoisted(() => ({ getCapabilities: vi.fn() }));

vi.mock('dashboard/api/contacts', () => ({
  default: {
    getCapabilities,
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    const getters = {
      getCurrentUser: ref({ id: 902, accounts: [{ id: 902, role: 'agent' }] }),
      'accounts/isFeatureEnabledonAccount': ref(() => false),
      'globalConfig/isOnChatwootCloud': ref(false),
      'globalConfig/isACustomBrandedInstance': ref(false),
    };
    return getters[getter];
  },
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: computed(() => 902) }),
}));

vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false, enterprisePlanName: 'community' }),
}));

vi.mock('dashboard/helper/permissionsHelper', () => ({
  getUserPermissions: () => [],
  hasPermissions: () => false,
}));

describe('usePolicy contact capabilities', () => {
  it('uses server capability values after the account capability response arrives', async () => {
    getCapabilities.mockResolvedValue({
      data: {
        domains: [
          {
            module: 'contacts',
            capabilities: {
              'contacts.read': false,
              'contacts.create': true,
              'contacts.update': false,
              'contacts.delete': false,
              'contacts.import': false,
              'contacts.export': false,
            },
          },
        ],
      },
    });

    let policy;
    const wrapper = mount(
      defineComponent({
        setup() {
          policy = usePolicy();
          return () => h('div');
        },
      }),
      { global: { plugins: [createStore({})] } }
    );

    expect(policy.checkContactPermission('contacts.read')).toBe(true);
    await flushPromises();
    expect(policy.checkContactPermission('contacts.read')).toBe(false);
    expect(policy.checkContactPermission('contacts.create')).toBe(true);
    expect(policy.checkContactPermission('contacts.update')).toBe(false);
    expect(policy.checkContactPermission('contacts.delete')).toBe(false);
    expect(policy.checkContactPermission('contacts.import')).toBe(false);
    expect(policy.checkContactPermission('contacts.export')).toBe(false);
    expect(
      policy.checkContactPermissions(['contacts.read', 'contacts.create'])
    ).toBe(false);
    expect(
      policy.checkContactPermissions(['contacts.read', 'contacts.export'])
    ).toBe(false);
    expect(
      policy.checkContactPermissions([
        'contacts.read',
        'contacts.update',
        'contacts.delete',
      ])
    ).toBe(false);
    expect(getCapabilities).toHaveBeenCalledWith(902);
    wrapper.unmount();
  });
});
