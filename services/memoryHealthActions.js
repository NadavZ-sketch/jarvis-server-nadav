'use strict';

// Applies a chosen action for a memory-health finding, reusing the same
// primitives the manual /memories CRUD endpoints already use (Pinecone +
// Obsidian cleanup on delete, scope flip on archive, category patch on move).

const pinecone = require('./pineconeMemory');
const obsidianSync = require('./obsidianSync');
const { classifyCategory } = require('./memoryCategory');

const ACTIONS_BY_TYPE = {
    duplicate: ['delete', 'merge'],
    conflict: ['archive'],
    category_mismatch: ['move'],
    stale: ['archive'],
    thin_content: ['delete'],
};

function invalidActionError(action, type) {
    const err = new Error(`Invalid action "${action}" for finding type "${type}"`);
    err.status = 400;
    return err;
}

async function deleteMemoryById(id, repos) {
    const rows = await repos.memories.removeById(id);
    const row = rows[0];
    if (row) {
        await pinecone.deleteMemory(row.id);
        obsidianSync.removeFromVault('memories', row);
    }
    return row;
}

async function archiveMemoryById(id, repos) {
    const rows = await repos.memories.updateById(id, { scope: 'archive' });
    await pinecone.deleteMemory(id).catch(() => {});
    return rows[0];
}

async function resolveFinding(finding, action, payload, repos) {
    const allowed = ACTIONS_BY_TYPE[finding.type] || [];
    if (!allowed.includes(action)) throw invalidActionError(action, finding.type);

    if (finding.type === 'duplicate') {
        if (action === 'delete') {
            const keepId = payload.keepId;
            const deleteId = String(finding.memory_id) === String(keepId) ? finding.related_memory_id : finding.memory_id;
            return deleteMemoryById(deleteId, repos);
        }
        if (action === 'merge') {
            const content = (payload.mergedContent || finding.suggested_payload?.mergedContent || '').trim();
            if (!content) throw Object.assign(new Error('mergedContent required'), { status: 400 });
            const category = await classifyCategory(content, false);
            const inserted = await repos.memories.create({ content, scope: 'long_term', category });
            const row = inserted[0];
            if (row?.id) await pinecone.upsertMemory(row.id, content).catch(() => {});
            await archiveMemoryById(finding.memory_id, repos);
            await archiveMemoryById(finding.related_memory_id, repos);
            return row;
        }
    }

    if (finding.type === 'conflict' && action === 'archive') {
        const archiveId = payload.archiveId || finding.related_memory_id;
        return archiveMemoryById(archiveId, repos);
    }

    if (finding.type === 'category_mismatch' && action === 'move') {
        const category = payload.category || finding.suggested_payload?.category;
        const rows = await repos.memories.updateById(finding.memory_id, { category });
        return rows[0];
    }

    if (finding.type === 'stale' && action === 'archive') {
        return archiveMemoryById(finding.memory_id, repos);
    }

    if (finding.type === 'thin_content' && action === 'delete') {
        return deleteMemoryById(finding.memory_id, repos);
    }

    throw invalidActionError(action, finding.type);
}

module.exports = { resolveFinding, ACTIONS_BY_TYPE };
