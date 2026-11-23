import * as types from '../../../mutation-types';
import { mutations } from '../../contactConversations';

describe('#mutations', () => {
  describe('#SET_CONTACT_CONVERSATIONS_UI_FLAG', () => {
    it('set ui flags', () => {
      const state = { uiFlags: { isFetching: true } };
      mutations[types.default.SET_CONTACT_CONVERSATIONS_UI_FLAG](state, {
        isFetching: false,
      });
      expect(state.uiFlags).toEqual({
        isFetching: false,
      });
    });
  });

  describe('#SET_CONTACT_CONVERSATIONS', () => {
    it('set contact conversation records', () => {
      const state = { records: {} };
      mutations[types.default.SET_CONTACT_CONVERSATIONS](state, {
        id: 1,
        data: [{ id: 1, contact_id: 1, message: 'hello' }],
      });
      expect(state.records).toEqual({
        1: [{ id: 1, contact_id: 1, message: 'hello' }],
      });
    });
  });

  describe('#DELETE_CONTACT_CONVERSATION', () => {
    it('clears history for one contact and keeps other contact caches', () => {
      const state = {
        records: { 1: [{ id: 11 }], 2: [{ id: 22 }] },
        neighbours: {},
      };

      mutations[types.default.DELETE_CONTACT_CONVERSATION](state, 1);

      expect(state.records).toEqual({ 2: [{ id: 22 }] });
    });
  });

  describe('#CLEAR_ALL_CONTACT_CONVERSATIONS', () => {
    it('clears history for every contact', () => {
      const state = {
        records: { 1: [{ id: 11 }], 2: [{ id: 22 }] },
        neighbours: { 13: [{ id: 11 }] },
      };

      mutations[types.default.CLEAR_ALL_CONTACT_CONVERSATIONS](state);

      expect(state.records).toEqual({});
      expect(state.neighbours).toEqual({ 13: [{ id: 11 }] });
    });
  });

  describe('#CLEAR_ALL_CONVERSATION_NEIGHBOURS', () => {
    it('clears all cached conversation neighbours', () => {
      const state = {
        records: { 1: [{ id: 11 }] },
        neighbours: { 13: [{ id: 11 }] },
      };

      mutations[types.default.CLEAR_ALL_CONVERSATION_NEIGHBOURS](state);

      expect(state.records).toEqual({ 1: [{ id: 11 }] });
      expect(state.neighbours).toEqual({});
    });
  });

  describe('#SET_CONVERSATION_NEIGHBOURS', () => {
    it('sets the neighbours of a conversation', () => {
      const state = { neighbours: {} };
      mutations[types.default.SET_CONVERSATION_NEIGHBOURS](state, {
        id: 13,
        data: [{ id: 11 }, { id: 13 }],
      });
      expect(state.neighbours).toEqual({
        13: [{ id: 11 }, { id: 13 }],
      });
    });
  });

  describe('#ADD_CONTACT_CONVERSATION', () => {
    it('Adds new contact conversation to records', () => {
      const state = { records: {} };
      mutations[types.default.ADD_CONTACT_CONVERSATION](state, {
        id: 1,
        data: { id: 1, contact_id: 1, message: 'hello' },
      });
      expect(state.records).toEqual({
        1: [{ id: 1, contact_id: 1, message: 'hello' }],
      });
    });
  });
});
