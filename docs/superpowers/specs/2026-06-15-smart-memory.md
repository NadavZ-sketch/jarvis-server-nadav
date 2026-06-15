# Smart Memory — Design Spec

## Goal

Replace the current passive, explicit-only memory system with a proactive system that:
1. Extracts facts, preferences, and active context automatically during every conversation
2. Detects conflicts with existing memories and asks the user inline before updating
3. Archives replaced memories instead of deleting them
4. Injects memories into chat context in a type-aware, proactive way

---

## Architecture

### Files Modified

| File | Change |
|------|--------|
| `agents/memoryAgent.js` | New 3-type extraction prompt, conflict detection, pending logic, session summary, archive |
| `agents/chatAgent.js` | Type-aware memory formatting, proactive usage instructions in system prompt |
| `server.js` | Check pending memories at request start; trigger session summary after 5+ turns |
| `services/obsidianSync.js` | Write to topic-organized files when `OBSIDIAN_VAULT_PATH` configured (optional) |

No Supabase schema changes required — `scope` already supports arbitrary string values.

---

## Memory Taxonomy

Three types, distinguished by a prefix tag in the `content` field:

| Type | Prefix | Examples | Lifecycle |
|------|--------|---------|-----------|
| `fact` | `[fact]` | lives in Jerusalem, allergic to penicillin, two kids | Permanent until user updates |
| `pref` | `[pref]` | prefers short answers, wakes at 6am, likes dark mode | Permanent until user updates |
| `context` | `[context]` | working on presentation for Thursday, considering apartment move | Auto-expires after 7 days |

---

## Feature 1: Improved Extraction

### Updated `AUTO_EXTRACT_PROMPT` in `memoryAgent.js`

The new prompt classifies content into all three types instead of the current `long_term` / `session` binary:

```javascript
const AUTO_EXTRACT_PROMPT = `
אתה מנתח שיחה ומחלץ עובדות אישיות חשובות לשמירה.

הודעת המשתמש: "{message}"
תגובת העוזר: "{answer}"

חלץ עד 3 פריטי מידע בעלי ערך לזיכרון ארוך טווח.
סווג כל פריט לאחת מהקטגוריות:
- [fact]: עובדה יציבה — משפחה, מקום מגורים, בריאות, עבודה, גיל
- [pref]: העדפה או דפוס התנהגות — מה אוהב, איך עובד, שגרת יום
- [context]: הקשר פעיל — פרויקט עכשווי, החלטה השבוע, מטרה קרובה

החזר JSON בפורמט:
{ "memories": [ { "type": "fact|pref|context", "content": "..." } ] }

כללים:
- רק מידע אישי ספציפי (לא שאלות כלליות)
- משפט אחד קצר לכל פריט
- אם אין מידע ראוי — החזר { "memories": [] }
`.trim();
```

### Relaxed Skip Conditions

**Remove** the skip for `reminder` and `notes` intents — these often contain personal information ("תזמין לי פיצה לבית בגבעתיים" = location).

**Keep** skipping: messages < 20 chars (was 30), weather/sports/news/stocks intents.

### Session Summary (`[context]` auto-save)

After every conversation with ≥ 5 turns, generate a 2-sentence summary saved as `[context]`:

```javascript
async function saveSessionSummary(chatId, supabase, history) {
  if (history.length < 5) return;
  const prompt = `סכם בשני משפטים קצרים את נושאי השיחה הבאה (בעברית):
${history.slice(-10).map(m => `${m.sender}: ${m.text}`).join('\n')}
החזר רק את הסיכום, ללא הסברים.`;
  const summary = await callGemma4(prompt);
  if (!summary) return;
  await saveMemory(`[context] ${summary.trim()}`, 'session', supabase);
  // No user confirmation needed for context summaries.
}
```

Called from `server.js` after the main response, alongside `autoExtractMemory`.

---

## Feature 2: Conflict Detection & Update Flow

When `autoExtractMemory` finds a candidate, it checks Pinecone for similar existing memories:

```
candidate similarity vs existing  →  action
──────────────────────────────────────────────
< 0.70                             →  new memory (ask user)
0.70 – 0.92                        →  update (ask user, show old)
> 0.92                             →  duplicate, skip silently
```

### Pending Memory Flow

Because `autoExtractMemory` runs fire-and-forget (after the response is sent), the confirmation is deferred to the **next request**:

1. Candidate found → stored in server-side TTL cache (key: `chatId`, TTL: 10 minutes) — no schema change needed
2. At the **start of the next request** for this `chatId`, server checks the TTL cache for a pending memory
3. If found, chatAgent is instructed to open its response with the confirmation question (in Hebrew, naturally)
4. User replies "כן" / "לא" → chatAgent detects intent from history, calls confirm/discard endpoint
5. `POST /memories/confirm` — saves or discards the pending memory, clears cache entry

### Pending Memory Cache Entry

```javascript
// pendingMemories TTL cache (10 min), keyed by chatId:
{
  content: '[fact] גר בירושלים',
  type: 'fact',
  replacesId: 'uuid-of-old-memory',      // undefined if new memory
  replacesContent: '[fact] גר בתל אביב', // undefined if new memory
}
```

### Confirmation Question Format

When pending memory exists, chatAgent prepends (naturally, in conversation):

- **New fact/pref:** *"שמתי לב שציינת שאתה גר בירושלים — האם לשמור לזיכרון?"*
- **Update:** *"שמתי לב שאתה גר בירושלים — זה שונה ממה שרשמתי (גר בתל אביב). לעדכן?"*

User responds → chatAgent interprets "כן"/"לא" from context and calls confirm/discard.

**`[context]` summaries**: Always auto-saved, no confirmation asked.

---

## Feature 3: Archive (not delete)

When a `[fact]` or `[pref]` memory is replaced:

1. Old memory in Supabase: `scope` updated to `'archive'`
2. Old memory removed from Pinecone (not searchable in regular queries)
3. New memory inserted in both Pinecone and Supabase (scope: `'long_term'`)

Archive is query-able explicitly:
```
User: "מה אמרתי בעבר על מקום מגורים?"
→ memoryAgent fetches scope='archive' from Supabase matching the topic
→ "בעבר ציינת שגרת בתל אביב, ולפני כן ברחובות"
```

**`[context]` summaries**: Hard-deleted when replaced (no archive — ephemeral by design).

---

## Feature 4: Smart Injection in `chatAgent`

### Memory Formatting in System Prompt

Replace the current flat memory list with a type-aware structured block:

```javascript
function formatMemories(memories) {
  const facts = memories.filter(m => m.content.startsWith('[fact]'));
  const prefs = memories.filter(m => m.content.startsWith('[pref]'));
  const ctx   = memories.filter(m => m.content.startsWith('[context]'));

  const clean = s => s.replace(/^\[(fact|pref|context)\]\s*/, '');
  const lines = [];
  if (facts.length) lines.push(`📌 עובדות: ${facts.map(m => clean(m.content)).join(' · ')}`);
  if (prefs.length) lines.push(`⭐ העדפות: ${prefs.map(m => clean(m.content)).join(' · ')}`);
  if (ctx.length)   lines.push(`🕐 הקשר אחרון: ${ctx.map(m => clean(m.content)).join(' · ')}`);
  return lines.join('\n');
}
```

### Proactive Usage Instruction

Added to the chatAgent system prompt:

```
זיכרונות המשתמש:
{formattedMemories}

הנחיות שימוש בזיכרון:
- שלב עובדות רלוונטיות בתשובה בצורה טבעית, ללא הכרזה מיוחדת
- כשמתאים, הזכר מה שנאמר בשיחות קודמות ("כמו שאמרת...")
- כשיש ספק לגבי העדפה, שאל ("אתה מעדיף תשובה קצרה כרגיל?")
```

### Retrieval Improvements

| Parameter | Current | New |
|-----------|---------|-----|
| Pinecone score threshold | 0.55 | 0.45 |
| Max memories loaded | 5 | 8 |
| Type diversity | none | at least 1 from each type if available |

---

## Feature 5: Obsidian Integration (Optional)

When `OBSIDIAN_VAULT_PATH` is configured, `obsidianSync.js` writes organized topic files:

```
Vault/
  Memories/
    Facts.md       ← all [fact] memories as bullet list
    Preferences.md ← all [pref] memories as bullet list
    Recent.md      ← last 5 [context] summaries with dates
```

User can edit these files directly in Obsidian → changes sync back on next 5-minute cron tick.

This is additive — the system works identically without Obsidian.

---

## New Endpoint: `POST /memories/confirm`

```javascript
// body: { chatId, action: 'save' | 'discard' }
// Finds the pending memory for chatId, saves or discards it
app.post('/memories/confirm', async (req, res) => {
  const { chatId, action } = req.body;
  // 1. Fetch pending memory for chatId from Supabase
  // 2. If action === 'save': upsert to Pinecone, update Supabase scope to 'long_term',
  //    archive old (replaces_id) if present
  // 3. If action === 'discard': delete pending entry
  // 4. Return { ok: true }
});
```

ChatAgent calls this automatically after detecting user confirmation in the conversation.

---

## Non-Goals

- No UI changes to the Flutter app (confirmation is inline in chat)
- No migration of existing memories to the new tag format (new extractions use tags; old ones work as-is)
- No Pinecone namespace changes
- No multi-memory confirmation in one turn (one pending per chatId at a time)
