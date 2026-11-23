import { onBeforeUnmount } from 'vue';
import ContactAPI from 'dashboard/api/contacts';

export function useProtectedContactMedia() {
  const objectUrlsBySource = new Map();
  const pendingRequestsBySource = new Map();
  let isDisposed = false;

  const resolveProtectedContactMediaUrl = async sourceUrl => {
    if (!sourceUrl) return '';
    if (!sourceUrl.startsWith('/api/v1/accounts/')) return sourceUrl;

    const cachedUrl = objectUrlsBySource.get(sourceUrl);
    if (cachedUrl) return cachedUrl;

    const pendingRequest = pendingRequestsBySource.get(sourceUrl);
    if (pendingRequest) return pendingRequest;

    const request = ContactAPI.fetchProtectedMedia(sourceUrl)
      .then(({ data }) => {
        const objectUrl = URL.createObjectURL(data);
        if (isDisposed) {
          URL.revokeObjectURL(objectUrl);
          return '';
        }

        objectUrlsBySource.set(sourceUrl, objectUrl);
        return objectUrl;
      })
      .catch(() => '')
      .finally(() => pendingRequestsBySource.delete(sourceUrl));

    pendingRequestsBySource.set(sourceUrl, request);
    return request;
  };

  onBeforeUnmount(() => {
    isDisposed = true;
    objectUrlsBySource.forEach(objectUrl => URL.revokeObjectURL(objectUrl));
    objectUrlsBySource.clear();
  });

  return { resolveProtectedContactMediaUrl };
}
