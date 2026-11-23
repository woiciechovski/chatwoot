import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ContactManageView from './ContactManageView.vue';
import ContactNotes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactNotes.vue';
import ContactHistory from 'dashboard/components-next/Contacts/ContactsSidebar/ContactHistory.vue';

const { dispatch, alert, route, router } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  alert: vi.fn(),
  route: { params: { accountId: '12', contactId: '34' } },
  router: { back: vi.fn(), push: vi.fn() },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => ({
    value:
      getter === 'contacts/getContactById'
        ? () => undefined
        : { isFetchingItem: false, isMerging: false, isUpdating: false },
  }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: alert }));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkContactPermission: () => true,
    checkContactPermissions: () => true,
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => router,
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('ContactManageView authorization errors', () => {
  beforeEach(() => {
    dispatch.mockReset();
    alert.mockReset();
    dispatch.mockImplementation(action => {
      if (action === 'contacts/show') {
        return Promise.reject(
          Object.assign(new Error('ERROR_WITH_MESSAGE'), {
            data: 'You are not authorized to access this account',
          })
        );
      }
      return Promise.resolve();
    });
  });

  it('shows the server denial and does not request inbox data for a denied contact', async () => {
    const wrapper = shallowMount(ContactManageView, {
      global: { mocks: { $t: key => key } },
    });
    await flushPromises();

    expect(alert).toHaveBeenCalledWith(
      'You are not authorized to access this account'
    );
    expect(dispatch).not.toHaveBeenCalledWith(
      'contacts/fetchContactableInbox',
      '34'
    );
    expect(dispatch).not.toHaveBeenCalledWith('contactNotes/get', {
      contactId: '34',
    });
    expect(dispatch).not.toHaveBeenCalledWith('contactConversations/get', '34');
    expect(wrapper.findComponent(ContactNotes).exists()).toBe(false);
    expect(wrapper.findComponent(ContactHistory).exists()).toBe(false);
    wrapper.unmount();
  });
});
