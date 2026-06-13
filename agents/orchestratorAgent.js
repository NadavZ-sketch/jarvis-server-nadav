require('dotenv').config();
const { callGemma4 } = require('./models');

const DETECT_PROMPT = `You are an intent analyzer for a Hebrew personal assistant.
Analyze the user message and determine if it contains MULTIPLE distinct actionable intents.

Known intents: task, reminder, memory, shopping, notes, messaging, draft, music, translate, weather, news, stocks, sports

A "multi-intent" message asks for 2+ DIFFERENT actions in one message.
Examples:
- "הוסף משימה לפגישה ותזכיר לי שעה לפני" → task + reminder ✓
- "שמור שאני אוהב פיצה ותזכיר לי לקנות ביום שישי" → memory + reminder ✓
- "מה מזג האוויר ומה החדשות?" → weather + news ✓
- "הוסף חלב לרשימת קניות ואורז" → shopping only (same intent, NOT multi) ✗
- "תגיד לי מה הן המשימות שלי" → task only ✗

Today's date context: you may use relative dates.

Respond ONLY with valid JSON (no explanation):
{ "isMultiIntent": true/false, "tasks": [ {"intent": "task|reminder|memory|shopping|notes|messaging|draft|weather|news|stocks|sports|music|translate", "message": "the sub-request in Hebrew"} ] }

If isMultiIntent is false, tasks can be empty array.

User message: `;

async function detectMultiIntent(userMessage) {
    try {
        const raw = await callGemma4(DETECT_PROMPT + userMessage, false, 300);
        const text = typeof raw === 'string' ? raw : (raw?.answer || raw?.content || '');
        const m = text.match(/\{[\s\S]*\}/);
        if (!m) return null;
        const parsed = JSON.parse(m[0]);
        if (!parsed.isMultiIntent || !Array.isArray(parsed.tasks) || parsed.tasks.length < 2) return null;
        return parsed;
    } catch {
        return null;
    }
}

async function dispatchSubTask(intent, message, supabase, useLocal, settings, chatHistory, longTermMemories) {
    try {
        switch (intent) {
            case 'task': {
                const { runTaskAgent } = require('./taskAgent');
                const { createRepos } = require('../services/dataAccess');
                return await runTaskAgent(message, createRepos(supabase), useLocal, settings);
            }
            case 'reminder': {
                const { runReminderAgent } = require('./reminderAgent');
                const { createRepos } = require('../services/dataAccess');
                return await runReminderAgent(message, createRepos(supabase));
            }
            case 'memory': {
                const { runMemoryAgent } = require('./memoryAgent');
                const { createRepos } = require('../services/dataAccess');
                return await runMemoryAgent(message, createRepos(supabase), useLocal, settings);
            }
            case 'shopping': {
                const { runShoppingAgent } = require('./shoppingAgent');
                const { createRepos } = require('../services/dataAccess');
                return await runShoppingAgent(message, createRepos(supabase), useLocal);
            }
            case 'notes': {
                const { runNotesAgent } = require('./notesAgent');
                const { createRepos } = require('../services/dataAccess');
                return await runNotesAgent(message, createRepos(supabase), useLocal);
            }
            case 'weather': {
                const { runWeatherAgent } = require('./weatherAgent');
                return await runWeatherAgent(message, settings);
            }
            case 'news': {
                const { runNewsAgent } = require('./newsAgent');
                return await runNewsAgent(message, settings);
            }
            case 'stocks': {
                const { runStocksAgent } = require('./stocksAgent');
                return await runStocksAgent(message);
            }
            case 'sports': {
                const { runSportsAgent } = require('./sportsAgent');
                return await runSportsAgent(message);
            }
            case 'translate': {
                const { runTranslationAgent } = require('./translationAgent');
                return await runTranslationAgent(message, supabase, useLocal);
            }
            case 'music': {
                const { runMusicAgent } = require('./musicAgent');
                return await runMusicAgent(message, supabase, useLocal, settings);
            }
            case 'draft': {
                const { runDraftAgent } = require('./draftAgent');
                return await runDraftAgent(message, chatHistory || [], longTermMemories || '', settings);
            }
            case 'messaging': {
                const { runMessagingAgent } = require('./messagingAgent');
                return await runMessagingAgent(message, supabase, useLocal);
            }
            default:
                return null;
        }
    } catch (err) {
        console.error(`🎭 Orchestrator sub-task error (${intent}):`, err.message);
        return null;
    }
}

async function runOrchestratorAgent(userMessage, supabase, useLocal, settings, chatHistory, longTermMemories) {
    // Quick pattern pre-check to avoid LLM call for simple messages
    const MULTI_HINT = /(?:(?:הוסף|תוסיף)\s+משימ.{3,50}(?:תזכיר|תזכורת))|(?:(?:תזכיר).{3,50}(?:הוסף|תוסיף)\s+משימ)|(?:שמור\s+ש.{3,40}(?:תזכיר|תוסיף))|(?:(?:מה\s+מזג\s+האוויר|מה\s+חדשות).{1,20}(?:ו|גם))|(?:ו\s*(?:גם|כן|תוסיף|תזכיר)\b)/i;
    if (!MULTI_HINT.test(userMessage)) return null;

    const multi = await detectMultiIntent(userMessage);
    if (!multi) return null;

    console.log(`🎭 Orchestrator: dispatching ${multi.tasks.length} sub-tasks`);

    const results = await Promise.allSettled(
        multi.tasks.map(t => dispatchSubTask(t.intent, t.message, supabase, useLocal, settings, chatHistory, longTermMemories))
    );

    const answers = results
        .map(r => r.status === 'fulfilled' && r.value?.answer ? r.value.answer : null)
        .filter(Boolean);

    if (answers.length === 0) return null;

    const combinedAnswer = answers.join('\n\n---\n\n');
    const actions = results
        .filter(r => r.status === 'fulfilled' && r.value?.action)
        .map(r => r.value.action);

    return {
        answer: combinedAnswer,
        action: actions.length === 1 ? actions[0] : (actions.length > 1 ? actions : null),
    };
}

module.exports = { runOrchestratorAgent };
