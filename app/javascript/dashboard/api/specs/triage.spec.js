/* global axios */
import triage from '../triage';
import ApiClient from '../ApiClient';

describe('#TriageAPI', () => {
  beforeEach(() => {
    vi.stubGlobal('axios', {
      get: vi.fn().mockResolvedValue({ data: {} }),
      post: vi.fn().mockResolvedValue({ data: {} }),
    });
  });

  it('uses the account-scoped triage route', () => {
    expect(triage).toBeInstanceOf(ApiClient);
    expect(triage.resource).toBe('triage/conversations');
    expect(triage.options.accountScoped).toBe(true);
  });

  it('requests the queue with the provided filters and transfers by team id', async () => {
    const params = { q: 'Taylor', inbox_id: 4, page: 2 };
    await triage.get(params);
    await triage.transfer(32, 9);

    expect(axios.get).toHaveBeenCalledWith(triage.url, {
      params,
      signal: undefined,
    });
    expect(axios.post).toHaveBeenCalledWith(`${triage.url}/32/transfer`, {
      team_id: 9,
    });
  });
});
