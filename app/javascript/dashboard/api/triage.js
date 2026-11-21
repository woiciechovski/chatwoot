/* global axios */
import ApiClient from './ApiClient';

class TriageAPI extends ApiClient {
  constructor() {
    super('triage/conversations', { accountScoped: true });
  }

  get(params, { signal } = {}) {
    return axios.get(this.url, { params, signal });
  }

  transfer(conversationId, teamId) {
    return axios.post(`${this.url}/${conversationId}/transfer`, {
      team_id: teamId,
    });
  }
}

export default new TriageAPI();
