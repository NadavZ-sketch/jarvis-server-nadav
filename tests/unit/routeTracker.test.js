'use strict';

jest.useFakeTimers();
const { setLastRoute, getLastRoute } = require('../../services/routeTracker');

describe('routeTracker', () => {
    it('returns null for an unknown chat', () => {
        expect(getLastRoute('never-seen')).toBeNull();
    });

    it('stores and retrieves the last route for a chat', () => {
        setLastRoute('chatA', { intent: 'weather', mode: 'fast' });
        expect(getLastRoute('chatA')).toEqual({ intent: 'weather', mode: 'fast' });
    });

    it('overwrites the previous route for the same chat', () => {
        setLastRoute('chatB', { intent: 'news', mode: 'fast' });
        setLastRoute('chatB', { intent: 'task', mode: 'llm' });
        expect(getLastRoute('chatB')).toEqual({ intent: 'task', mode: 'llm' });
    });

    it('ignores a falsy chatId without throwing', () => {
        expect(() => setLastRoute('', { intent: 'chat' })).not.toThrow();
        expect(getLastRoute('')).toBeNull();
    });

    it('expires entries after the TTL', () => {
        setLastRoute('chatC', { intent: 'memory', mode: 'fast' });
        expect(getLastRoute('chatC')).not.toBeNull();
        jest.advanceTimersByTime(11 * 60 * 1000); // past the 10-minute TTL
        expect(getLastRoute('chatC')).toBeNull();
    });
});
