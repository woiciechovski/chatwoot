import { flushPromises, shallowMount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import articlesAPI from 'dashboard/api/helpCenter/articles';
import PortalsArticlesEditPage from '../PortalsArticlesEditPage.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn(), useRouter: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: vi.fn(),
  useMapGetter: vi.fn(),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock('dashboard/api/helpCenter/articles', () => ({
  default: { getPreviewToken: vi.fn() },
}));
vi.mock(
  'dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue',
  () => ({ default: { name: 'ArticleEditor', template: '<div />' } })
);

const makeArticle = id => ({
  id,
  slug: `article-${id}`,
  status: 'draft',
  category: { slug: 'general', locale: 'en' },
});

describe('PortalsArticlesEditPage signed preview navigation', () => {
  let route;
  let dispatch;
  let open;

  beforeEach(() => {
    vi.stubGlobal('chatwootConfig', { hostURL: 'https://app.example.com' });
    route = reactive({ params: { articleSlug: '1', portalSlug: 'help' } });
    dispatch = vi.fn().mockResolvedValue({});
    useRoute.mockReturnValue(route);
    useRouter.mockReturnValue({ push: vi.fn() });
    useStore.mockReturnValue({ dispatch });
    useMapGetter.mockImplementation(key =>
      ref(key === 'articles/articleById' ? makeArticle : () => ({}))
    );
    articlesAPI.getPreviewToken.mockImplementation(({ id }) =>
      Promise.resolve({ data: { preview_token: `token-${id}` } })
    );
    open = vi.spyOn(window, 'open').mockImplementation(() => null);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('uses route values to load the article and open its signed preview', async () => {
    const wrapper = shallowMount(PortalsArticlesEditPage);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('articles/show', {
      id: '1',
      portalSlug: 'help',
    });
    expect(articlesAPI.getPreviewToken).toHaveBeenCalledWith({
      id: '1',
      portalSlug: 'help',
    });
    wrapper.findComponent({ name: 'ArticleEditor' }).vm.$emit('previewArticle');
    expect(open).toHaveBeenCalledWith(
      expect.stringContaining('/hc/help/articles/article-1?preview=token-1'),
      '_blank'
    );
    wrapper.unmount();
  });

  it('clears the old token while the next article is loading', async () => {
    const wrapper = shallowMount(PortalsArticlesEditPage);
    await flushPromises();
    let resolveToken;
    articlesAPI.getPreviewToken.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveToken = resolve;
        })
    );
    route.params.articleSlug = '2';
    await flushPromises();
    wrapper.findComponent({ name: 'ArticleEditor' }).vm.$emit('previewArticle');

    expect(open).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      'HELP_CENTER.EDIT_ARTICLE_PAGE.HEADER.PREVIEW_NOT_READY'
    );
    resolveToken({ data: { preview_token: 'token-2' } });
    await flushPromises();
    wrapper.findComponent({ name: 'ArticleEditor' }).vm.$emit('previewArticle');
    expect(open).toHaveBeenCalledWith(
      expect.stringContaining('/articles/article-2?preview=token-2'),
      '_blank'
    );
    wrapper.unmount();
  });

  it('ignores a late token response for the previous article', async () => {
    let resolveFirstToken;
    articlesAPI.getPreviewToken.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirstToken = resolve;
        })
    );
    const wrapper = shallowMount(PortalsArticlesEditPage);
    route.params.articleSlug = '2';
    await flushPromises();
    resolveFirstToken({ data: { preview_token: 'token-1' } });
    await flushPromises();
    wrapper.findComponent({ name: 'ArticleEditor' }).vm.$emit('previewArticle');

    expect(open).toHaveBeenCalledWith(
      expect.stringContaining('/articles/article-2?preview=token-2'),
      '_blank'
    );
    wrapper.unmount();
  });
});
