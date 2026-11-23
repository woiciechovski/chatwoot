import types from '../mutation-types';

export const isContactReadDenied = error =>
  [401, 403].includes(error.response?.status);

export const clearContactReadCaches = commit => {
  commit(`contacts/${types.CLEAR_CONTACTS}`, null, { root: true });
  commit(`contactNotes/${types.CLEAR_ALL_CONTACT_NOTES}`, null, {
    root: true,
  });
  commit(
    `contactConversations/${types.CLEAR_ALL_CONTACT_CONVERSATIONS}`,
    null,
    { root: true }
  );
  commit(
    `contactConversations/${types.CLEAR_ALL_CONVERSATION_NEIGHBOURS}`,
    null,
    { root: true }
  );
};
