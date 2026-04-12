require('dotenv').config();
const fs   = require('fs');
const path = require('path');
const { callGemma4 } = require('./models');

const CUSTOM_DIR  = path.join(__dirname, 'custom');
const REGISTRY    = path.join(CUSTOM_DIR, 'registry.json');
const PENDING     = path.join(CUSTOM_DIR, 'pending.json');

// ─── Registry helpers ─────────────────────────────────────────────────────────

function loadRegistry() {
    try { return JSON.parse(fs.readFileSync(REGISTRY, 'utf8')); } catch { return []; }
}

function saveRegistry(data) {
    if (!fs.existsSync(CUSTOM_DIR)) fs.mkdirSync(CUSTOM_DIR, { recursive: true });
    fs.writeFileSync(REGISTRY, JSON.stringify(data, null, 2));
}

// ─── Pending helpers ──────────────────────────────────────────────────────────

function loadPending() {
    try { return JSON.parse(fs.readFileSync(PENDING, 'utf8')); } catch { return null; }
}

function savePending(data) {
    if (!fs.existsSync(CUSTOM_DIR)) fs.mkdirSync(CUSTOM_DIR, { recursive: true });
    fs.writeFileSync(PENDING, JSON.stringify(data, null, 2));
}

function clearPending() {
    try { fs.unlinkSync(PENDING); } catch { /* ok */ }
}

function capitalize(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

// ─── Confirm / Cancel ─────────────────────────────────────────────────────────

function confirmPendingAgent() {
    const pending = loadPending();
    if (!pending) return { answer: 'אין אייג\'נט ממתין לאישור.' };

    const registry = loadRegistry();
    const idx = registry.findIndex(r => r.name === pending.entry.name);
    if (idx >= 0) registry[idx] = pending.entry;
    else registry.push(pending.entry);
    saveRegistry(registry);
    clearPending();

    const keywords = pending.entry.keywords.join(' | ') || '—';
    return {
        answer: [
            `✅ האייג'נט **${pending.entry.displayName}** שולב באפליקציה ופעיל!`,
            `🔑 הפעלה: ${keywords}`,
        ].join('\n'),
    };
}

function cancelPendingAgent() {
    const pending = loadPending();
    if (!pending) return { answer: 'אין אייג\'נט ממתין לביטול.' };

    const name = pending.entry.displayName;
    try { fs.unlinkSync(pending.entry.filePath); } catch { /* ok */ }
    clearPending();

    return { answer: `בסדר, האייג'נט "${name}" לא נשמר ונמחק.` };
}

// ─── Prompts ──────────────────────────────────────────────────────────────────

function buildDesignPrompt(request) {
    return `You are an expert AI agent designer for a Hebrew personal assistant (Node.js/Express).
Design a new agent based on the user request below. Return ONLY valid JSON (no markdown):

{
  "agentName": "camelCase unique name, e.g. weatherAgent",
  "displayName": "שם תצוגה בעברית",
  "purpose": "תיאור מה האייג'נט עושה, 2-3 משפטים",
  "keywords": ["מילת מפתח 1", "מילת מפתח 2", "מילת מפתח 3"],
  "capabilities": ["יכולת 1", "יכולת 2", "יכולת 3"],
  "systemPrompt": "System prompt that defines the agent's role and behavior in Hebrew",
  "exampleUsage": ["דוגמה לשימוש 1", "דוגמה לשימוש 2"]
}

User request: "${request}"`;
}

function buildCodePrompt(design) {
    const fnName = `run${capitalize(design.agentName)}`;
    return `Write a complete Node.js agent file for a Hebrew AI assistant. Return ONLY raw JavaScript, no markdown, no explanation.

Agent spec:
- Name: ${design.agentName}
- Purpose: ${design.purpose}
- System prompt: ${design.systemPrompt}

STRICT REQUIREMENTS:
1. Start with: require('dotenv').config();
2. Import: const { callGemma4 } = require('../models');
3. Export exactly: module.exports = { ${fnName} };
4. Function signature: async function ${fnName}(userMessage, supabase, useLocal, settings = {})
5. Always return: { answer: "..." }
6. Wrap everything in try-catch, return Hebrew error on failure
7. Use the system prompt from the spec to guide responses
8. Respond in Hebrew only`;
}

// ─── Demo runner ──────────────────────────────────────────────────────────────

async function runDemo(filePath, agentName, sampleQuery, supabase, useLocal) {
    try {
        // Clear require cache so we get the freshly written file
        delete require.cache[require.resolve(filePath)];
        const mod = require(filePath);
        const fnName = `run${capitalize(agentName)}`;
        if (typeof mod[fnName] !== 'function') {
            return `(הפונקציה ${fnName} לא נמצאה בקובץ שנוצר)`;
        }
        const result = await mod[fnName](sampleQuery, supabase, useLocal, {});
        return result.answer || '(ללא תשובה)';
    } catch (err) {
        return `(שגיאה בהרצת הדמו: ${err.message})`;
    }
}

// ─── List / Delete ────────────────────────────────────────────────────────────

function listAgents() {
    const registry = loadRegistry();
    if (registry.length === 0) {
        return { answer: 'אין אייג\'נטים מותאמים אישית עדיין. תוכל ליצור אחד על ידי תיאור מה אתה צריך.' };
    }
    const list = registry.map((a, i) =>
        `${i + 1}. **${a.displayName}** (${a.name})\n   מילות מפתח: ${a.keywords.join(' | ')}`
    ).join('\n\n');
    return { answer: `האייג'נטים שיצרת:\n\n${list}` };
}

function deleteAgent(userMessage) {
    const registry = loadRegistry();
    const toDelete = userMessage
        .replace(/מחק אייג'נט|הסר אייג'נט|מחק סוכן/gi, '')
        .replace(/\b(את|ה)\b/g, '')
        .trim();

    const idx = registry.findIndex(a =>
        a.name.toLowerCase().includes(toDelete.toLowerCase()) ||
        a.displayName.includes(toDelete)
    );
    if (idx === -1) return { answer: `לא מצאתי אייג'נט בשם "${toDelete}".` };

    const removed = registry[idx];
    registry.splice(idx, 1);
    saveRegistry(registry);
    try { fs.unlinkSync(path.join(CUSTOM_DIR, `${removed.name}.js`)); } catch { /* ok */ }

    return { answer: `מחקתי את האייג'נט "${removed.displayName}".` };
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function runAgentFactoryAgent(userMessage, supabase, useLocal) {
    try {
        // ── Confirm pending agent ──────────────────────────────────────────────
        if (/^(כן|אשר|yes|approve|אוקי|בסדר|שלב)$/i.test(userMessage.trim()) ||
            /אשר.*אייג'נט|שלב.*אייג'נט/i.test(userMessage)) {
            return confirmPendingAgent();
        }

        // ── Cancel pending agent ───────────────────────────────────────────────
        if (/^(לא|בטל|cancel|no|ביטול|אל תשלב)$/i.test(userMessage.trim()) ||
            /בטל.*אייג'נט.*ממתין|אל תשלב/i.test(userMessage)) {
            return cancelPendingAgent();
        }

        // ── List agents ────────────────────────────────────────────────────────
        if (/רשימת אייג'נטים|הצג אייג'נטים|אילו אייג'נטים|כמה אייג'נטים/i.test(userMessage)) {
            return listAgents();
        }

        // ── Delete agent ───────────────────────────────────────────────────────
        if (/מחק אייג'נט|הסר אייג'נט|מחק סוכן/i.test(userMessage)) {
            return deleteAgent(userMessage);
        }

        // ── Create agent ───────────────────────────────────────────────────────
        console.log('🏭 AgentFactory: designing agent...');

        // Step 1: Design
        const designRaw = await callGemma4(buildDesignPrompt(userMessage), false);
        const designMatch = designRaw.match(/\{[\s\S]*"agentName"[\s\S]*\}/);
        if (!designMatch) throw new Error('לא הצלחתי לעצב את האייג\'נט');

        let design;
        try { design = JSON.parse(designMatch[0]); }
        catch { throw new Error('תכנון האייג\'נט הגיע בפורמט לא תקין'); }

        design.agentName = design.agentName.replace(/[^a-zA-Z0-9]/g, '').replace(/^./, c => c.toLowerCase());
        if (!design.agentName) throw new Error('שם האייג\'נט לא תקין');

        console.log(`🏭 AgentFactory: generating code for "${design.agentName}"...`);

        // Step 2: Generate code
        const generatedCode = await callGemma4(buildCodePrompt(design), false);
        const cleanCode = generatedCode
            .replace(/^```(?:javascript|js)?\n?/, '')
            .replace(/\n?```$/, '')
            .trim();

        // Step 3: Write file (pending — not in registry yet)
        if (!fs.existsSync(CUSTOM_DIR)) fs.mkdirSync(CUSTOM_DIR, { recursive: true });
        const filePath = path.join(CUSTOM_DIR, `${design.agentName}.js`);
        fs.writeFileSync(filePath, cleanCode, 'utf8');
        console.log(`🏭 AgentFactory: wrote ${filePath} (pending approval)`);

        // Step 4: Run demo
        const sampleQuery = (Array.isArray(design.exampleUsage) && design.exampleUsage[0])
            ? design.exampleUsage[0]
            : design.purpose;

        console.log(`🏭 AgentFactory: running demo with "${sampleQuery}"...`);
        const demoAnswer = await runDemo(filePath, design.agentName, sampleQuery, supabase, useLocal);

        // Step 5: Save to pending (not registry)
        const entry = {
            name: design.agentName,
            displayName: design.displayName || design.agentName,
            keywords: Array.isArray(design.keywords) ? design.keywords : [],
            filePath,
        };
        savePending({ entry, design });

        // Step 6: Return demo + confirmation request
        const caps     = Array.isArray(design.capabilities) ? design.capabilities.map(c => `• ${c}`).join('\n') : '';
        const keywords = entry.keywords.join(' | ') || '—';

        return {
            answer: [
                `🤖 יצרתי אייג'נט: **${entry.displayName}**`,
                `📋 ${design.purpose}`,
                caps ? `\n⚙️ יכולות:\n${caps}` : '',
                `\n🔑 מילות מפתח: ${keywords}`,
                '',
                `🧪 **ניסיון עם השאילתה:** "${sampleQuery}"`,
                '─────────────────────────',
                demoAnswer,
                '─────────────────────────',
                '',
                '❓ האם לשלב את האייג\'נט באפליקציה?',
                '• "כן" / "אשר" — לשלב',
                '• "לא" / "בטל" — לא לשמור',
            ].filter(Boolean).join('\n'),
        };

    } catch (err) {
        console.error('AgentFactory Error:', err.message);
        return { answer: `סליחה, לא הצלחתי ליצור את האייג'נט. ${err.message}` };
    }
}

module.exports = { runAgentFactoryAgent };
