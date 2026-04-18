// Obsidian Vault ⇄ Supabase bidirectional sync
// Vault layout documented in plans/tender-sprouting-kazoo.md

const fs         = require('fs');
const path       = require('path');
const crypto     = require('crypto');
const chokidar   = require('chokidar');
const matter     = require('gray-matter');
const simpleGit  = require('simple-git');

let vaultPath    = null;
let supabase     = null;
let git          = null;
let watcher      = null;
let syncState    = {};          // { relPath: { hash, updated_at, id } }
let debounceJobs = new Map();   // relPath → timer
let suppressUntil = new Map();  // relPath → timestamp (ignore watcher events we triggered ourselves)

const ENTITY_DIRS = {
    notes:        'Notes',
    memories:     'Memories',
    tasks:        'Tasks',
    reminders:    'Reminders',
    chat_history: 'Chat History',
    projects:     'Projects',
};

const SYNC_STATE_FILE = path.join('_meta', 'sync-state.json');

// ─── helpers ─────────────────────────────────────────────────────────────────

function hashContent(content) {
    return crypto.createHash('sha1').update(content).digest('hex').slice(0, 12);
}

function sanitizeFilename(str) {
    return String(str || 'untitled')
        .replace(/[\\/:*?"<>|]/g, '_')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 80) || 'untitled';
}

function ensureDirSync(dir) {
    fs.mkdirSync(dir, { recursive: true });
}

function readSyncState() {
    const p = path.join(vaultPath, SYNC_STATE_FILE);
    try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return {}; }
}

function writeSyncState() {
    const p = path.join(vaultPath, SYNC_STATE_FILE);
    ensureDirSync(path.dirname(p));
    fs.writeFileSync(p, JSON.stringify(syncState, null, 2));
}

function relFromVault(absPath) {
    return path.relative(vaultPath, absPath).split(path.sep).join('/');
}

function absInVault(relPath) {
    return path.join(vaultPath, ...relPath.split('/'));
}

// ─── Entity ↔ file mapping ───────────────────────────────────────────────────

function filePathForRecord(entity, record) {
    const dir = ENTITY_DIRS[entity];
    if (entity === 'notes') {
        const name = sanitizeFilename(record.title || record.content?.slice(0, 40) || record.id);
        return `${dir}/${name}.md`;
    }
    if (entity === 'memories') {
        const cat = extractCategory(record.content) || 'General';
        return `${dir}/${sanitizeFilename(cat)}.md`;
    }
    if (entity === 'tasks')     return `${dir}/tasks.md`;
    if (entity === 'reminders') return `${dir}/reminders.md`;
    return `${dir}/${sanitizeFilename(record.id || 'unknown')}.md`;
}

function extractCategory(content) {
    const m = String(content || '').match(/^\[([^\]]+)\]/);
    return m ? m[1].trim() : null;
}

// ─── DB → Vault ──────────────────────────────────────────────────────────────

function writeEntityFile(entity, record) {
    if (!vaultPath) return;
    const relPath  = filePathForRecord(entity, record);
    const absPath  = absInVault(relPath);
    ensureDirSync(path.dirname(absPath));

    let body;
    let frontmatter;

    if (entity === 'notes') {
        frontmatter = {
            id:         record.id,
            type:       'note',
            title:      record.title || '',
            category:   record.category || 'Personal',
            created_at: record.created_at,
        };
        body = record.content || '';
    } else if (entity === 'memories') {
        // Append-style: one file per category, each memory is a line with its id
        const existing = fs.existsSync(absPath) ? matter.read(absPath) : { data: { type: 'memories', category: extractCategory(record.content) || 'General' }, content: '' };
        const line     = `- [${record.id}] ${record.content}`;
        if (!existing.content.includes(`[${record.id}]`)) {
            existing.content = (existing.content.trim() + '\n' + line).trim() + '\n';
        }
        frontmatter = { ...existing.data, updated_at: new Date().toISOString() };
        body = existing.content;
    } else if (entity === 'tasks') {
        return upsertListFile(entity, record, absPath, (r) =>
            `- [${r.done ? 'x' : ' '}] ${r.title || r.content} <!-- id:${r.id} -->`
        );
    } else if (entity === 'reminders') {
        return upsertListFile(entity, record, absPath, (r) =>
            `- [ ] ${r.title || r.content} — 📅 ${r.due_at || r.remind_at || ''} <!-- id:${r.id} -->`
        );
    } else {
        frontmatter = { id: record.id, type: entity, created_at: record.created_at };
        body = record.content || '';
    }

    const output = matter.stringify(body, frontmatter);
    writeFileSuppressed(absPath, output);
    syncState[relPath] = { hash: hashContent(output), id: record.id, updated_at: record.updated_at || record.created_at };
    writeSyncState();
}

function upsertListFile(entity, record, absPath, lineFormatter) {
    ensureDirSync(path.dirname(absPath));
    let existing = { data: { type: entity }, content: '' };
    if (fs.existsSync(absPath)) existing = matter.read(absPath);

    const newLine = lineFormatter(record);
    const lines   = existing.content.split('\n');
    const idTag   = `<!-- id:${record.id} -->`;
    const idx     = lines.findIndex(l => l.includes(idTag));

    if (idx >= 0) lines[idx] = newLine;
    else          lines.push(newLine);

    const body = lines.filter(l => l.trim().length > 0).join('\n') + '\n';
    const out  = matter.stringify(body, { ...existing.data, updated_at: new Date().toISOString() });
    writeFileSuppressed(absPath, out);

    const rel = relFromVault(absPath);
    syncState[rel] = { hash: hashContent(out), updated_at: new Date().toISOString() };
    writeSyncState();
}

function writeFileSuppressed(absPath, content) {
    suppressUntil.set(relFromVault(absPath), Date.now() + 2000);
    fs.writeFileSync(absPath, content, 'utf8');
}

async function appendChatMessage(role, text, timestamp) {
    if (!vaultPath) return;
    const ts      = timestamp ? new Date(timestamp) : new Date();
    const date    = ts.toISOString().slice(0, 10);
    const relPath = `${ENTITY_DIRS.chat_history}/${date}.md`;
    const absPath = absInVault(relPath);
    ensureDirSync(path.dirname(absPath));

    const time    = ts.toTimeString().slice(0, 5);
    const speaker = role === 'user' ? 'אתה' : 'ג׳רביס';
    const line    = `**${time} — ${speaker}:** ${text}\n\n`;

    let existing = { data: { type: 'chat_history', date }, content: '' };
    if (fs.existsSync(absPath)) existing = matter.read(absPath);

    existing.content = (existing.content.trim() + '\n\n' + line).trim() + '\n';
    const out = matter.stringify(existing.content, { ...existing.data, updated_at: new Date().toISOString() });
    writeFileSuppressed(absPath, out);
    syncState[relPath] = { hash: hashContent(out), updated_at: new Date().toISOString() };
    writeSyncState();
}

// ─── Vault → DB ──────────────────────────────────────────────────────────────

async function fileToDb(absPath) {
    if (!supabase) return;
    const relPath = relFromVault(absPath);

    // Ignore files we just wrote ourselves
    const suppress = suppressUntil.get(relPath);
    if (suppress && Date.now() < suppress) return;

    if (!fs.existsSync(absPath)) return;
    const raw   = fs.readFileSync(absPath, 'utf8');
    const hash  = hashContent(raw);
    if (syncState[relPath] && syncState[relPath].hash === hash) return; // no change

    const parsed = matter(raw);
    const type   = parsed.data.type;
    const topDir = relPath.split('/')[0];

    try {
        if (type === 'note' || topDir === 'Notes') {
            await upsertNote(parsed);
        } else if (type === 'memories' || topDir === 'Memories') {
            await upsertMemoriesFile(parsed);
        } else if (type === 'tasks' || topDir === 'Tasks') {
            await upsertListFromFile('tasks', parsed);
        } else if (type === 'reminders' || topDir === 'Reminders') {
            await upsertListFromFile('reminders', parsed);
        }
        syncState[relPath] = { hash, updated_at: new Date().toISOString() };
        writeSyncState();
    } catch (err) {
        console.error(`[ObsidianSync] fileToDb failed for ${relPath}:`, err.message);
    }
}

async function upsertNote(parsed) {
    const { data, content } = parsed;
    const payload = {
        title:    data.title || '',
        content:  content.trim(),
        category: data.category || 'Personal',
    };
    if (data.id) {
        await supabase.from('notes').update(payload).eq('id', data.id);
    } else {
        const { data: inserted } = await supabase.from('notes').insert([payload]).select().single();
        if (inserted?.id) {
            data.id = inserted.id;
            // rewrite with id in frontmatter (no-op if already present)
        }
    }
}

async function upsertMemoriesFile(parsed) {
    const lines = parsed.content.split('\n').filter(l => l.trim().startsWith('- '));
    const cat   = parsed.data.category || 'General';
    for (const line of lines) {
        const idMatch = line.match(/\[([0-9a-f-]{8,})\]/);
        const text    = line.replace(/^- (\[[^\]]+\]\s*)?/, '').trim();
        const payload = { content: `[${cat}] ${text}` };
        if (idMatch) {
            await supabase.from('memories').update(payload).eq('id', idMatch[1]);
        } else {
            await supabase.from('memories').insert([payload]);
        }
    }
}

async function upsertListFromFile(table, parsed) {
    const lines = parsed.content.split('\n').filter(l => /^-\s*\[.\]/.test(l));
    for (const line of lines) {
        const idMatch = line.match(/<!--\s*id:([^\s]+)\s*-->/);
        const done    = /\[x\]/i.test(line);
        const title   = line.replace(/^-\s*\[.\]\s*/, '').replace(/<!--.*?-->/, '').replace(/📅.*$/, '').trim();
        const payload = { title, done };
        if (idMatch) {
            await supabase.from(table).update(payload).eq('id', idMatch[1]);
        } else {
            await supabase.from(table).insert([payload]);
        }
    }
}

// ─── Watcher ─────────────────────────────────────────────────────────────────

function handleFileChange(absPath) {
    const rel = relFromVault(absPath);
    if (rel.startsWith('_meta/')) return;
    if (debounceJobs.has(rel)) clearTimeout(debounceJobs.get(rel));
    debounceJobs.set(rel, setTimeout(() => {
        debounceJobs.delete(rel);
        fileToDb(absPath).catch(e => console.error('[ObsidianSync] watcher:', e.message));
    }, 500));
}

// ─── Git ─────────────────────────────────────────────────────────────────────

async function gitPull() {
    if (!git) return { ok: false, reason: 'no-git' };
    try {
        await git.pull('origin', 'main', { '--rebase': 'true' });
        return { ok: true };
    } catch (err) {
        console.error('[ObsidianSync] git pull failed:', err.message);
        return { ok: false, reason: err.message };
    }
}

async function gitPush(message = `Jarvis auto-sync ${new Date().toISOString()}`) {
    if (!git) return { ok: false, reason: 'no-git' };
    try {
        const status = await git.status();
        if (status.files.length === 0) return { ok: true, reason: 'nothing-to-commit' };
        await git.add('.');
        await git.commit(message);
        await git.push('origin', 'main');
        return { ok: true };
    } catch (err) {
        console.error('[ObsidianSync] git push failed:', err.message);
        return { ok: false, reason: err.message };
    }
}

// ─── Public API ──────────────────────────────────────────────────────────────

async function initSync({ vaultPath: vp, supabase: sb, enableWatch = true, enableGit = true }) {
    vaultPath = vp;
    supabase  = sb;
    if (!vaultPath) {
        console.log('[ObsidianSync] OBSIDIAN_VAULT_PATH not set — sync disabled');
        return;
    }
    if (!fs.existsSync(vaultPath)) {
        console.warn(`[ObsidianSync] vault path does not exist: ${vaultPath}`);
        return;
    }

    // ensure structure
    for (const dir of Object.values(ENTITY_DIRS)) ensureDirSync(path.join(vaultPath, dir));
    ensureDirSync(path.join(vaultPath, 'Projects', 'Work'));
    ensureDirSync(path.join(vaultPath, 'Projects', 'Personal'));
    syncState = readSyncState();

    if (enableGit) {
        try {
            git = simpleGit({ baseDir: vaultPath });
            const isRepo = await git.checkIsRepo().catch(() => false);
            if (!isRepo) {
                console.log('[ObsidianSync] vault is not a git repo — git sync skipped');
                git = null;
            } else {
                await gitPull();
            }
        } catch (err) {
            console.warn('[ObsidianSync] git init failed:', err.message);
        }
    }

    if (enableWatch) {
        watcher = chokidar.watch(vaultPath, {
            ignored: /(^|[\/\\])(\.|_meta)/,
            ignoreInitial: true,
            persistent: true,
        });
        watcher.on('add',    handleFileChange);
        watcher.on('change', handleFileChange);
    }

    console.log(`[ObsidianSync] initialized at ${vaultPath} (git=${!!git}, watch=${!!watcher})`);
}

async function safeSelect(table, query = '*', order = null) {
    try {
        let q = supabase.from(table).select(query);
        if (order) q = q.order(order, { ascending: true });
        const { data, error } = await q;
        if (error) { console.warn(`[ObsidianSync] ${table} fetch skipped:`, error.message); return []; }
        return data || [];
    } catch (e) { return []; }
}

async function fullSyncFromDb() {
    if (!vaultPath || !supabase) return { ok: false, reason: 'not-initialized' };
    let counts = { notes: 0, memories: 0, tasks: 0, reminders: 0, contacts: 0, chat_history: 0 };
    try {
        const [notes, memories, tasks, reminders, contacts, chat] = await Promise.all([
            safeSelect('notes',       '*', 'created_at'),
            safeSelect('memories',    '*', 'created_at'),
            safeSelect('tasks'),
            safeSelect('reminders'),
            safeSelect('contacts'),
            safeSelect('chat_history','*', 'created_at'),
        ]);

        for (const r of notes)     { writeEntityFile('notes',     r); counts.notes++; }
        for (const r of memories)  { writeEntityFile('memories',  r); counts.memories++; }
        for (const r of tasks)     { writeEntityFile('tasks',     { ...r, title: r.content || r.title }); counts.tasks++; }
        for (const r of reminders) { writeEntityFile('reminders', { ...r, title: r.text || r.title, remind_at: r.scheduled_time }); counts.reminders++; }

        // Contacts — כל איש קשר = שורה ב-contacts.md
        if (contacts.length > 0) {
            ensureDirSync(path.join(vaultPath, 'Contacts'));
            const absPath = path.join(vaultPath, 'Contacts', 'contacts.md');
            const lines = contacts.map(c =>
                `- **${c.name || c.full_name || '?'}** | ${c.phone || ''} | ${c.email || ''} <!-- id:${c.id} -->`
            ).join('\n');
            const out = matter.stringify(lines + '\n', { type: 'contacts', updated_at: new Date().toISOString() });
            writeFileSuppressed(absPath, out);
            counts.contacts = contacts.length;
        }

        // Chat history — קובץ לכל יום
        for (const r of chat) {
            await appendChatMessage(r.role, r.text, r.created_at);
            counts.chat_history++;
        }

        console.log(`[ObsidianSync] fullSync done:`, counts);
        return { ok: true, counts };
    } catch (err) {
        console.error('[ObsidianSync] fullSync error:', err.message);
        return { ok: false, reason: err.message };
    }
}

async function syncAll() {
    if (!vaultPath) return { ok: false, reason: 'not-initialized' };
    const pull     = await gitPull();
    const syncResult = await fullSyncFromDb();
    const push     = await gitPush();
    return { ok: true, pull, push, sync: syncResult };
}

function dbToVault(entity, record) {
    if (!vaultPath || !record) return;
    try {
        writeEntityFile(entity, record);
    } catch (err) {
        console.error(`[ObsidianSync] dbToVault(${entity}):`, err.message);
    }
}

function stop() {
    if (watcher) { watcher.close(); watcher = null; }
}

module.exports = {
    initSync,
    syncAll,
    fullSyncFromDb,
    dbToVault,
    appendChatMessage,
    gitPull,
    gitPush,
    stop,
    // test exports
    _internals: { hashContent, extractCategory, filePathForRecord, sanitizeFilename, ENTITY_DIRS },
};
