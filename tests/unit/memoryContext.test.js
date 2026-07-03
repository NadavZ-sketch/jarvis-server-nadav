'use strict';

jest.mock('../../services/pineconeMemory', () => ({
    upsertMemory: jest.fn().mockResolvedValue(true),
    deleteMemory: jest.fn().mockResolvedValue(),
    isReady: jest.fn().mockReturnValue(false),
    searchMemories: jest.fn().mockResolvedValue(null),
}));
jest.mock('../../services/obsidianSync', () => ({ dbToVault: jest.fn(), removeFromVault: jest.fn() }));
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn() }));

const pinecone = require('../../services/pineconeMemory');
const { classifyCategory } = require('../../services/memoryCategory');
const memoryContext = require('../../services/memoryContext');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => jest.clearAllMocks());

describe('savePendingData', () => {
    test('classifies and persists a category on the new memory', async () => {
        classifyCategory.mockResolvedValue('משפחה');
        const repos = makeRepos({ memories: [{ id: 5 }] });
        await memoryContext.savePendingData({ content: '[fact] יש לי שני ילדים' }, repos);
        expect(classifyCategory).toHaveBeenCalledWith('[fact] יש לי שני ילדים', false);
        expect(repos.memories.insert).toHaveBeenCalledWith({
            content: '[fact] יש לי שני ילדים', scope: 'long_term', category: 'משפחה',
        });
    });

    test('archives the old memory when replacing an existing one', async () => {
        classifyCategory.mockResolvedValue('כללי');
        const repos = makeRepos({ memories: [{ id: 5 }] });
        await memoryContext.savePendingData({ content: '[fact] x', replacesId: 3 }, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith(3, { scope: 'archive' });
        expect(pinecone.deleteMemory).toHaveBeenCalledWith(3);
    });
});
