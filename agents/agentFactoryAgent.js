'use strict';

const path = require('path');
const fs = require('fs');
const { callGemma4 } = require('./models');

const CUSTOM_DIR   = path.resolve(__dirname, 'custom');
const REGISTRY_PATH = path.join(CUSTOM_DIR, 'registry.json');

// ─── Registry I/O ─────────────────────────────────────────────────────────────

function readRegistry() {
    try { return JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8')); }
    catch { return []; }
}

function writeRegistry(entries) {
    fs.mkdirSync(CUSTOM_DIR, { recursive: true });
    const tmp = `${REGISTRY_PATH}.tmp.${process.pid}`;
    fs.writeFileSync(tmp, JSON.stringify(entries, null, 2), 'utf8');
    fs.renameSync(tmp, REGISTRY_PATH);
    // Bust the router's 30 s cache so the new agent is hot-loadable immediately.
    try { require('./router').invalidateRouterCache(); } catch { /* non-fatal */ }
}

// ─── Name validation ──────────────────────────────────────────────────────────

function sanitizeAgentName(raw) {
    // ASCII camelCase only, 3–30 chars — no path separators, no Hebrew in the name
    const clean = (raw || '').trim().replace(/\s+(.)/g, (_, c) => c.toUpperCase());
    return /^[a-zA-Z][a-zA-Z0-9]{2,29}$/.test(clean) ? clean : null;
}

// ─── Code safety gate ─────────────────────────────────────────────────────────

const BLOCKED_MODULES = /require\s*\(\s*['"`](?:child_process|net|cluster|dgram|vm)\b/i;

function isCodeSafe(code) {
    if (!code.includes('module.exports')) return false;
    if (BLOCKED_MODULES.test(code))       return false;
    if (/\beval\s*\(/.test(code))         return false;
    return true;
}

// ─── Code generation ─────────────────────────────────────────────────────────

async function generateAgentCode(agentName, description, useLocal) {
    const fnName = `run${agentName.charAt(0).toUpperCase() + agentName.slice(1)}`;
    const prompt = `Write a minimal Node.js agent module for the Jarvis Hebrew assistant.

Agent name: ${agentName}
Purpose: ${description}

Requirements:
- Export ONLY: module.exports = { ${fnName} };
- Signature: async function ${fnName}(userMessage, repos, useLocal, settings)
- Return { answer: string }  (action is optional)
- Respond in Hebrew
- If LLM needed: const { callGemma4 } = require('../models');
- Max 35 lines; NO require of child_process, net, cluster, vm, dgram, eval

Return ONLY the JavaScript code, no markdown fences, no explanation:`;

    const raw = await callGemma4(prompt, useLocal, 500);
    const text = typeof raw === 'string' ? raw : (raw?.answer || '');
    const m = text.match(/```(?:javascript|js)?\s*([\s\S]*?)```/);
    return (m ? m[1] : text).trim();
}

// ─── Individual actions ───────────────────────────────────────────────────────

async function createAgent(agentName, description, useLocal) {
    const registry = readRegistry();
    if (registry.some(e => e.name === agentName)) {
        return { answer: `⚠️ סוכן בשם "${agentName}" כבר קיים.` };
    }

    const code = await generateAgentCode(agentName, description, useLocal);
    if (!isCodeSafe(code)) {
        return { answer: '❌ הקוד שנוצר אינו עומד בדרישות האבטחה — הסוכן לא נשמר.' };
    }

    const filePath = path.join(CUSTOM_DIR, `${agentName}.js`);
    fs.writeFileSync(filePath, code, 'utf8');

    // filePath stored relative to project root so tryCustomAgent can resolve it
    const relPath = `agents/custom/${agentName}.js`;
    registry.push({ name: agentName, filePath: relPath, description, createdAt: new Date().toISOString() });
    writeRegistry(registry);

    return {
        answer: `✅ סוכן "${agentName}" נוצר בהצלחה!\n📄 ${relPath}\n\nניתן לפנות אליו ישירות בשיחה.`,
        action: { type: 'agent_created', agentName, description },
    };
}

function listAgents() {
    const registry = readRegistry();
    if (registry.length === 0) return { answer: '📋 אין עדיין סוכנים מותאמים אישית.' };
    const lines = registry.map(e => {
        const date = e.createdAt ? new Date(e.createdAt).toLocaleDateString('he-IL') : '';
        return `• **${e.name}** — ${e.description || 'ללא תיאור'}${date ? ` _(${date})_` : ''}`;
    });
    return { answer: `🤖 *הסוכנים המותאמים שלך:*\n${lines.join('\n')}` };
}

function deleteAgent(agentName) {
    const registry = readRegistry();
    const idx = registry.findIndex(e => e.name === agentName);
    if (idx === -1) return { answer: `⚠️ לא נמצא סוכן בשם "${agentName}".` };

    const entry = registry[idx];
    const filePath = path.resolve(CUSTOM_DIR, '..', '..', entry.filePath);
    if (filePath.startsWith(CUSTOM_DIR + path.sep)) {
        try { fs.unlinkSync(filePath); } catch { /* already gone */ }
    }

    registry.splice(idx, 1);
    writeRegistry(registry);

    return {
        answer: `🗑️ סוכן "${agentName}" נמחק בהצלחה.`,
        action: { type: 'agent_deleted', agentName },
    };
}

// ─── Main agent ───────────────────────────────────────────────────────────────

async function runAgentFactoryAgent(userMessage, repos, useLocal, settings) {
    // List
    if (/רשימת סוכנים|הסוכנים שלי|הצג סוכנים|סוכנים קיימים|אילו סוכנים|סוכנים מותאמים/i.test(userMessage)) {
        return listAgents();
    }

    // Delete
    const delMatch = userMessage.match(/(?:מחק|הסר|בטל)\s+סוכן\s+["״]?([a-zA-Z][a-zA-Z0-9]{2,29})["״]?/i);
    if (delMatch) {
        const name = sanitizeAgentName(delMatch[1]);
        if (!name) return { answer: '⚠️ שם הסוכן אינו תקין.' };
        return deleteAgent(name);
    }

    // Create — "צור סוכן [name] ש[description]" / "בנה סוכן [name]: [description]"
    const createMatch = userMessage.match(
        /(?:צור|בנה|הוסף)\s+סוכן\s+["״]?([a-zA-Z][a-zA-Z0-9]{2,29})["״]?(?:\s+(?:ש|שי|שמ|ל|:|-)\s*(.{5,300}))?/i
    );
    if (createMatch) {
        const name = sanitizeAgentName(createMatch[1]);
        if (!name) return { answer: '⚠️ שם הסוכן אינו תקין. השתמש בשם באנגלית בלבד (לדוגמה: weatherHelper).' };
        const description = (createMatch[2] || createMatch[1]).trim();
        return await createAgent(name, description, useLocal);
    }

    return {
        answer: 'ניהול סוכנים מותאמים:\n• **צור סוכן** [שם] — [תיאור]\n• **רשימת סוכנים**\n• **מחק סוכן** [שם]',
    };
}

module.exports = { runAgentFactoryAgent, sanitizeAgentName, isCodeSafe, readRegistry };
