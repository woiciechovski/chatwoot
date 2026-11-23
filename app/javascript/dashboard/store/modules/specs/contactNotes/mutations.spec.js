import types from '../../../mutation-types';
import { mutations } from '../../contactNotes';
import allNotes from './fixtures';

describe('#mutations', () => {
  describe('#SET_CONTACT_NOTES', () => {
    it('set allNotes records', () => {
      const state = { records: {} };
      mutations[types.SET_CONTACT_NOTES](state, {
        data: allNotes,
        contactId: 1,
      });
      expect(state.records).toEqual({ 1: allNotes });
    });
  });
  describe('#CLEAR_CONTACT_NOTES', () => {
    it('clears notes for one contact and keeps other contact caches', () => {
      const state = { records: { 1: allNotes, 2: allNotes } };

      mutations[types.CLEAR_CONTACT_NOTES](state, 1);

      expect(state.records).toEqual({ 2: allNotes });
    });
  });
  describe('#CLEAR_ALL_CONTACT_NOTES', () => {
    it('clears cached notes for every contact', () => {
      const state = { records: { 1: allNotes, 2: allNotes } };

      mutations[types.CLEAR_ALL_CONTACT_NOTES](state);

      expect(state.records).toEqual({});
    });
  });

  describe('#ADD_CONTACT_NOTE', () => {
    it('push newly created note to the store', () => {
      const state = { records: { 1: [allNotes[0]] } };
      mutations[types.ADD_CONTACT_NOTE](state, {
        data: allNotes[1],
        contactId: 1,
      });
      expect(state.records[1]).toEqual([allNotes[0], allNotes[1]]);
    });
  });
  describe('#DELETE_CONTACT_NOTE', () => {
    it('Delete existing note from records', () => {
      const state = { records: { 1: [{ id: 2 }] } };
      mutations[types.DELETE_CONTACT_NOTE](state, {
        noteId: 2,
        contactId: 1,
      });
      expect(state.records[1]).toEqual([]);
    });
  });
});
