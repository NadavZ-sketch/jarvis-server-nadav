require('dotenv').config();
const fs   = require('fs');
const path = require('path');
const { callGemma4 } = require('./models');

const CUSTOM_DIR  = path.join(__dirname, 'custom');
const REGISTRY    = path.join(CUSTOM_DIR, 'registry.json');

// ─── Registry helpers ─────────────────────────────────────────────────────────

function loadRegistry() {
    try { return JSON.parse(fs.readFileSync(REGISTRY, 'utf8')); } catch { return []; }
}

function saveRegistry(data) {
    if (!fs.existsSync(CUSTOM_DIR)) fs.mkdirSync(CUSTOM_DIR, { recursive: true });
    fs.writeFileSync(REGISTRY, JSON.stringify(data, null, 2));
}

function capitalize(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

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

// ─── List command ─────────────────────────────────────────────────────────────

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

// ─── Delete command ───────────────────────────────────────────────────────────

function deleteAgent(userMessage) {
    const registry = loadRegistry();
    const toDelete = userMessage
        .replace(/מחק אייג'נט|הסר אייג'נט|מחק סוכן|בטל אייג'נט/gi, '')
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

    // Remove the file
    try { fs.unlinkSync(path.join(CUSTOM_DIR, `${removed.name}.js`)); } catch { /* ok */ }

    return { answer: `מחקתי את האייג'נט "${removed.displayName}" (${removed.name}).` };
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function runAgentFactoryAgent(userMessage, useLocal) {
    try {
        // List agents
        if (/רשימת אייג'נטים|הצג אייג'נטים|אילו אייג'נטים|כמה אייג'נטים/i.test(userMessage)) {
            return listAgents();
        }

        // Delete agent
        if (/מחק אייג'נט|הסר אייג'נט|מחק סוכן|בטל אייג'נט/i.test(userMessage)) {
            return deleteAgent(userMessage);
        }

        // Create agent
        console.log('🏭 AgentFactory: designing agent...');

        // Step 1: Design
        const designRaw = await callGemma4(buildDesignPrompt(userMessage), false);
        const designMatch = designRaw.match(/\{[\s\S]*"agentName"[\s\S]*\}/);
        if (!designMatch) throw new Error('לא הצלחתי לעצב את האייג\'נט');

        let design;
        try { design = JSON.parse(designMatch[0]); }
        catch { throw new Error('תכנון האייג\'נט הגיע בפורמט לא תקין'); }

        // Sanitize agent name (alphanumeric + camelCase only)
        design.agentName = design.agentName.replace(/[^a-zA-Z0-9]/g, '').replace(/^./, c => c.toLowerCase());
        if (!design.agentName) throw new Error('שם האייג\'נט לא תקין');

        console.log(`🏭 AgentFactory: generating code for "${design.agentName}"...`);

        // Step 2: Generate code
        const generatedCode = await callGemma4(buildCodePrompt(design), false);
        const cleanCode = generatedCode
            .replace(/^```(?:javascript|js)?\n?/, '')
            .replace(/\n?```$/, '')
            .trim();

        // Step 3: Write agent file
        if (!fs.existsSync(CUSTOM_DIR)) fs.mkdirSync(CUSTOM_DIR, { recursive: true });
        const filePath = path.join(CUSTOM_DIR, `${design.agentName}.js`);
        fs.writeFileSync(filePath, cleanCode, 'utf8');
        console.log(`🏭 AgentFactory: wrote ${filePath}`);

        // Step 4: Update registry
        const registry = loadRegistry();
        const entry = {
            name: design.agentName,
            displayName: design.displayName || design.agentName,
            keywords: Array.isArray(design.keywords) ? design.keywords : [],
            filePath,
        };
        const existing = registry.findIndex(r => r.name === design.agentName);
        if (existing >= 0) registry[existing] = entry;
        else registry.push(entry);
        saveRegistry(registry);

        // Step 5: Build response
        const keywordsStr = entry.keywords.join(' | ') || '—';
        const caps = Array.isArray(design.capabilities) ? design.capabilities.map(c => `• ${c}`).join('\n') : '';
        const examples = Array.isArray(design.exampleUsage) ? design.exampleUsage.map(e => `• "${e}"`).join('\n') : '';

        return {
            answer: [
                `✅ יצרתי את האייג'נט **${entry.displayName}**`,
                '',
                `📋 תפקיד: ${design.purpose}`,
                caps  ? `\n⚙️ יכולות:\n${caps}` : '',
                `\n🔑 מילות מפתח להפעלה:\n${keywordsStr}`,
                examples ? `\n💬 דוגמאות:\n${examples}` : '',
                '\n🔄 האייג\'נט פעיל מהבקשה הבאה.',
            ].filter(Boolean).join('\n'),
        };

    } catch (err) {
        console.error('AgentFactory Error:', err.message);
        return { answer: `סליחה, לא הצלחתי ליצור את האייג'נט. ${err.message}` };
    }
}

module.exports = { runAgentFactoryAgent };
