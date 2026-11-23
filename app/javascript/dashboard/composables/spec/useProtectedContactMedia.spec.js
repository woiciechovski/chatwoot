import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { useProtectedContactMedia } from '../useProtectedContactMedia';

const { fetchProtectedMedia } = vi.hoisted(() => ({
  fetchProtectedMedia: vi.fn(),
}));

vi.mock('dashboard/api/contacts', () => ({
  default: { fetchProtectedMedia },
}));

describe('useProtectedContactMedia', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it('fetches protected media once and revokes its object URL when unmounted', async () => {
    const createObjectURL = vi.fn(() => 'blob:contact-avatar');
    const revokeObjectURL = vi.fn();
    vi.stubGlobal('URL', { createObjectURL, revokeObjectURL });
    fetchProtectedMedia.mockResolvedValue({ data: new Blob(['avatar']) });

    let media;
    const wrapper = mount(
      defineComponent({
        setup() {
          media = useProtectedContactMedia();
          return () => h('div');
        },
      })
    );
    const avatarUrl = '/api/v1/accounts/7/contacts/42/avatar/download';

    await expect(
      media.resolveProtectedContactMediaUrl(avatarUrl)
    ).resolves.toBe('blob:contact-avatar');
    await media.resolveProtectedContactMediaUrl(avatarUrl);

    expect(fetchProtectedMedia).toHaveBeenCalledTimes(1);
    wrapper.unmount();
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:contact-avatar');
  });
});
