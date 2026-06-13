'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { runShoppingAgent } = require('../../agents/shoppingAgent');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => jest.clearAllMocks());

describe('runShoppingAgent', () => {
    it('adds item to shopping list', async () => {
        const repos = makeRepos({ shopping: [] });
        const result = await runShoppingAgent('הוסף חלב לרשימה', repos, false);
        expect(repos.shopping.add).toHaveBeenCalledWith('חלב');
        expect(result.answer).toContain('הוספתי');
    });

    it('shows shopping list', async () => {
        const repos = makeRepos({ shopping: [{ item: 'חלב' }, { item: 'לחם' }] });
        const result = await runShoppingAgent('מה יש ברשימה', repos, false);
        expect(repos.shopping.listOpen).toHaveBeenCalled();
        expect(result.answer).toContain('חלב');
    });

    it('empty list → empty message', async () => {
        const result = await runShoppingAgent('מה יש ברשימה', makeRepos({ shopping: [] }), false);
        expect(result.answer).toContain('ריקה');
    });

    it('deletes a matching item', async () => {
        const repos = makeRepos({ shopping: [{ item: '100%_מיץ' }] });
        const result = await runShoppingAgent('מחק 100%_מיץ מהרשימה', repos, false);
        expect(repos.shopping.deleteMatching).toHaveBeenCalledWith('100%_מיץ');
        expect(result.answer).toContain('הסרתי');
    });
});
