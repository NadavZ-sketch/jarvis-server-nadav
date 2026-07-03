'use strict';

jest.mock('../../services/pineconeMemory', () => ({
    deleteMemory: jest.fn().mockResolvedValue(),
    upsertMemory: jest.fn().mockResolvedValue(true),
}));
jest.mock('../../services/obsidianSync', () => ({ removeFromVault: jest.fn() }));
jest.mock('../../services/memoryCategory', () => ({ classifyCategory: jest.fn().mockResolvedValue('כללי') }));

const pinecone = require('../../services/pineconeMemory');
const obsidianSync = require('../../services/obsidianSync');
const { resolveFinding, ACTIONS_BY_TYPE } = require('../../services/memoryHealthActions');
const { makeRepos } = require('../helpers/fakeRepos');

beforeEach(() => jest.clearAllMocks());

describe('resolveFinding — duplicate', () => {
    test('delete removes the non-kept side', async () => {
        const repos = makeRepos({ memories: [{ id: 1, content: 'A' }] });
        repos.memories.removeById = jest.fn(async () => [{ id: 2, content: 'B' }]);
        const finding = { type: 'duplicate', memory_id: '1', related_memory_id: '2' };
        await resolveFinding(finding, 'delete', { keepId: '1' }, repos);
        expect(repos.memories.removeById).toHaveBeenCalledWith('2');
        expect(pinecone.deleteMemory).toHaveBeenCalledWith(2);
        expect(obsidianSync.removeFromVault).toHaveBeenCalledWith('memories', { id: 2, content: 'B' });
    });

    test('merge creates a new memory and archives both originals', async () => {
        const repos = makeRepos();
        repos.memories.create = jest.fn(async () => [{ id: 9, content: 'merged text' }]);
        repos.memories.updateById = jest.fn(async () => [{ id: 1, scope: 'archive' }]);
        const finding = { type: 'duplicate', memory_id: '1', related_memory_id: '2', suggested_payload: { mergedContent: 'merged text' } };
        const row = await resolveFinding(finding, 'merge', {}, repos);
        expect(repos.memories.create).toHaveBeenCalledWith({ content: 'merged text', scope: 'long_term', category: 'כללי' });
        expect(pinecone.upsertMemory).toHaveBeenCalledWith(9, 'merged text');
        expect(repos.memories.updateById).toHaveBeenCalledWith('1', { scope: 'archive' });
        expect(repos.memories.updateById).toHaveBeenCalledWith('2', { scope: 'archive' });
        expect(row).toEqual({ id: 9, content: 'merged text' });
    });

    test('merge uses the caller-supplied payload over the stored suggestion', async () => {
        const repos = makeRepos();
        repos.memories.create = jest.fn(async () => [{ id: 9, content: 'edited by user' }]);
        repos.memories.updateById = jest.fn(async () => [{}]);
        const finding = { type: 'duplicate', memory_id: '1', related_memory_id: '2', suggested_payload: { mergedContent: 'original suggestion' } };
        await resolveFinding(finding, 'merge', { mergedContent: 'edited by user' }, repos);
        expect(repos.memories.create).toHaveBeenCalledWith({ content: 'edited by user', scope: 'long_term', category: 'כללי' });
    });
});

describe('resolveFinding — conflict', () => {
    test('archive flips the chosen memory to scope=archive', async () => {
        const repos = makeRepos();
        repos.memories.updateById = jest.fn(async () => [{ id: 2, scope: 'archive' }]);
        const finding = { type: 'conflict', memory_id: '1', related_memory_id: '2' };
        await resolveFinding(finding, 'archive', { archiveId: '2' }, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith('2', { scope: 'archive' });
        expect(pinecone.deleteMemory).toHaveBeenCalledWith('2');
    });
});

describe('resolveFinding — category_mismatch', () => {
    test('move updates the category', async () => {
        const repos = makeRepos();
        repos.memories.updateById = jest.fn(async () => [{ id: 1, category: 'תחביב' }]);
        const finding = { type: 'category_mismatch', memory_id: '1', suggested_payload: { category: 'תחביב' } };
        await resolveFinding(finding, 'move', {}, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith('1', { category: 'תחביב' });
    });
});

describe('resolveFinding — stale / thin_content', () => {
    test('stale archive archives the single memory', async () => {
        const repos = makeRepos();
        repos.memories.updateById = jest.fn(async () => [{ id: 1, scope: 'archive' }]);
        await resolveFinding({ type: 'stale', memory_id: '1' }, 'archive', {}, repos);
        expect(repos.memories.updateById).toHaveBeenCalledWith('1', { scope: 'archive' });
    });

    test('thin_content delete removes the single memory', async () => {
        const repos = makeRepos();
        repos.memories.removeById = jest.fn(async () => [{ id: 1, content: 'x' }]);
        await resolveFinding({ type: 'thin_content', memory_id: '1' }, 'delete', {}, repos);
        expect(repos.memories.removeById).toHaveBeenCalledWith('1');
    });
});

describe('resolveFinding — invalid action', () => {
    test('rejects an action not valid for the finding type with a 400-flavored error', async () => {
        const repos = makeRepos();
        await expect(resolveFinding({ type: 'thin_content', memory_id: '1' }, 'merge', {}, repos))
            .rejects.toMatchObject({ status: 400 });
    });
});

test('ACTIONS_BY_TYPE enumerates the allowed action per finding type', () => {
    expect(ACTIONS_BY_TYPE).toEqual({
        duplicate: ['delete', 'merge'],
        conflict: ['archive'],
        category_mismatch: ['move'],
        stale: ['archive'],
        thin_content: ['delete'],
    });
});
