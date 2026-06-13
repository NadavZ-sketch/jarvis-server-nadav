// ─── Centralized agent dispatcher ─────────────────────────────────────────
//
// Single source of truth for which intent maps to which agent and how it's
// invoked. Both /ask-jarvis and /stream-jarvis route through this registry so
// the dispatch chain isn't duplicated and so the inconsistent agent call
// signatures (some take `settings`, some don't, some take history/memories)
// are isolated to one place — the per-entry `invoke` adapter.
//
// Adding a new agent: import the run* function in server.js, add it to the
// AGENTS object passed to dispatch(), add an entry below.
//
// `ctx` shape (built by server.js per request):
//   { userMessage, supabase, repos, useLocal, settings, chatHistory,
//     longTermMemories, imageBase64, sendEmail, chatId }
//   `repos` is the data-access seam bundle (services/dataAccess); agents that
//   have been migrated receive it instead of the raw `supabase` client.
//
// Entry shape:
//   {
//     mode:        'sync' | 'background',
//     invoke(ctx, agents):  call the underlying run* fn with its real arg order,
//     placeholder?:         (sync skipped) immediate Hebrew reply for 'background',
//     cacheBust?:           cache key to invalidate after a successful sync run,
//   }
//
// The orchestrator / custom-agent / chat fallback (`agentName` not in registry)
// stays in server.js because it weaves in capability-gap detection and image
// handling specific to /ask-jarvis.

const REGISTRY = {
    task:       { mode:'sync', invoke:(c,a) => a.runTaskAgent(c.userMessage, c.repos, c.useLocal, c.settings) },
    reminder:   { mode:'sync', invoke:(c,a) => a.runReminderAgent(c.userMessage, c.repos) },
    memory:     { mode:'sync', invoke:(c,a) => a.runMemoryAgent(c.userMessage, c.supabase, c.useLocal, c.settings), cacheBust: 'memories' },
    weather:    { mode:'sync', invoke:(c,a) => a.runWeatherAgent(c.userMessage, c.settings) },
    news:       { mode:'sync', invoke:(c,a) => a.runNewsAgent(c.userMessage, c.settings) },
    shopping:   { mode:'sync', invoke:(c,a) => a.runShoppingAgent(c.userMessage, c.supabase, c.useLocal) },
    notes:      { mode:'sync', invoke:(c,a) => a.runNotesAgent(c.userMessage, c.supabase, c.useLocal) },
    habit:      { mode:'sync', invoke:(c,a) => a.runHabitAgent(c.userMessage, c.supabase, c.useLocal, c.settings) },
    insight:    { mode:'sync', invoke:(c,a) => a.runInsightAgent(c.userMessage, c.supabase, c.useLocal, c.settings) },
    stocks:     { mode:'sync', invoke:(c,a) => a.runStocksAgent(c.userMessage) },
    translate:  { mode:'sync', invoke:(c,a) => a.runTranslationAgent(c.userMessage, c.supabase, c.useLocal) },
    music:      { mode:'sync', invoke:(c,a) => a.runMusicAgent(c.userMessage, c.supabase, c.useLocal, c.settings) },
    sports:     { mode:'sync', invoke:(c,a) => a.runSportsAgent(c.userMessage) },
    messaging:  { mode:'sync', invoke:(c,a) => a.runMessagingAgent(c.userMessage, c.supabase, c.useLocal, c.settings) },
    draft:      { mode:'sync', invoke:(c,a) => a.runDraftAgent(c.userMessage, c.chatHistory, c.longTermMemories, c.settings) },
    calendar:   { mode:'sync', invoke:(c,a) => a.runCalendarAgent(c.userMessage, c.supabase, c.settings) },
    prompt:     { mode:'sync', invoke:(c,a) => a.runPromptAgent(c.userMessage, c.supabase, c.useLocal, c.settings) },
    settings:   { mode:'sync', invoke:(c,a) => a.runSettingsAgent(c.userMessage, c.supabase, c.useLocal, c.settings) },
    project:    { mode:'sync', invoke:(c,a) => a.runProjectAgent(c.userMessage, c.supabase, c.useLocal, c.settings) },

    // 'security' is sync in /ask-jarvis but background in /stream-jarvis today.
    // Keep that parity: the dispatch caller decides which mode to use via
    // getEntryForMode() (see below).
    security: {
        mode:'sync',
        invoke:(c,a) => a.runSecurityAgent(c.userMessage, c.useLocal, c.sendEmail),
        backgroundPlaceholder: '🔒 סורק אבטחה ברקע — התוצאה תופיע בשיחה בקרוב.',
    },

    manus: {
        mode:'background',
        invoke:(c,a) => a.runManusAgent(c.userMessage, c.settings),
        placeholder: '🦾 Manus מתחיל לעבוד על המשימה ברקע — זה עשוי לקחת כמה דקות. התוצאה תופיע בשיחה כשתסיים.',
    },

    code_error: {
        mode:'background',
        invoke:(c,a) => a.runCodeErrorAgent(c.userMessage, c.useLocal, c.sendEmail),
        placeholder: '🔍 מתחיל סריקת שגיאות קוד ברקע — הדוח יופיע בשיחה כשיסיים. רענן את השיחה כדי לראות את התוצאות.',
    },
    e2e: {
        mode:'background',
        invoke:(c,a) => a.runE2EAgent(c.userMessage, c.supabase, c.useLocal, c.settings),
        placeholder: '🧪 מתחיל בדיקות קצה ברקע — הדוח המלא יופיע בשיחה כשיסיים (בד"כ תוך 1-2 דקות). רענן את השיחה כדי לראות את התוצאות.',
    },
};

function getEntry(agentName) {
    return REGISTRY[agentName] || null;
}

// Some agents (security) run sync in one route and background in another.
// Pass forceBackground:true to opt into the background variant when the entry
// exposes a backgroundPlaceholder.
function getEntryForMode(agentName, { forceBackground = false } = {}) {
    const entry = REGISTRY[agentName];
    if (!entry) return null;
    if (forceBackground && entry.backgroundPlaceholder) {
        return { ...entry, mode: 'background', placeholder: entry.backgroundPlaceholder };
    }
    return entry;
}

// Run a sync entry. Returns the agent's result; caller handles persistence.
async function dispatch(agentName, ctx, agents) {
    const entry = REGISTRY[agentName];
    if (!entry) throw new Error(`No registry entry for agent "${agentName}"`);
    if (entry.mode !== 'sync') throw new Error(`Agent "${agentName}" is not sync`);
    return entry.invoke(ctx, agents);
}

module.exports = { REGISTRY, getEntry, getEntryForMode, dispatch };
