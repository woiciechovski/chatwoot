import conversationFlows from '../conversationFlows';
import ApiClient from '../ApiClient';

describe('#ConversationFlowsAPI', () => {
  it('uses the account-scoped API client', () => {
    expect(conversationFlows).toBeInstanceOf(ApiClient);
    expect(conversationFlows.resource).toBe('conversation_flows');
    expect(conversationFlows.options.accountScoped).toBe(true);
  });
});
