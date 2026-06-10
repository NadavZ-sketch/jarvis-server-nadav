'use strict';

/**
 * Persistent system event logger.
 *
 * Writes to console AND the Supabase `system_events` table.
 * Never throws — logging must never break application flow.
 *
 * Critical-level events trigger a push notification, rate-limited
 * to one push per unique fingerprint per 6 hours.
 */

const CRITICAL_COOLDOWN_MS = 6 * 60 * 60 * 1000;
const _lastCriticalPushAt = new Map(); // fingerprint → timestamp

let _supabase = null;
let _pushService = null;

function init(supabaseClient, pushService) {
    _supabase = supabaseClient;
    _pushService = pushService;
}

/**
 * Build a short dedup fingerprint from source + first line of message.
 */
function _fingerprint(source, message) {
    const firstLine = String(message || '').split('\n')[0].slice(0, 120);
    return `${source}::${firstLine}`;
}

/**
 * Log an event at any level.
 * @param {'info'|'warn'|'error'|'critical'} level
 * @param {string} source   - e.g. 'cron:morning_briefing', 'agent:chatAgent'
 * @param {string} message
 * @param {object} [meta]   - extra context (serialised to JSON)
 */
async function logEvent(level, source, message, meta = {}) {
    const fp = _fingerprint(source, message);

    // Always log to console
    const consoleFn = level === 'error' || level === 'critical' ? console.error
        : level === 'warn' ? console.warn
        : console.log;
    consoleFn(`[${level.toUpperCase()}] [${source}] ${message}`, meta && Object.keys(meta).length ? meta : '');

    // Persist to Supabase (best-effort)
    if (_supabase) {
        try {
            await _supabase.from('system_events').insert([{
                level,
                source,
                message: String(message).slice(0, 2000),
                meta: meta && Object.keys(meta).length ? meta : null,
                fingerprint: fp,
                acked: false,
            }]);
        } catch (_) { /* never block on logging */ }
    }

    // Push for critical errors with 6h cooldown per fingerprint
    if (level === 'critical' && _pushService) {
        const last = _lastCriticalPushAt.get(fp);
        if (!last || (Date.now() - last) > CRITICAL_COOLDOWN_MS) {
            _lastCriticalPushAt.set(fp, Date.now());
            _pushService.sendPush({
                title: '🚨 ג׳רביס — שגיאה קריטית',
                body: `[${source}] ${String(message).slice(0, 200)}`,
                category: 'alert',
            }).catch(() => {});
        }
    }
}

/**
 * Log an error (automatically extracts stack trace).
 * @param {string} source
 * @param {Error|string} err
 * @param {object} [meta]
 */
async function logError(source, err, meta = {}) {
    const message = err instanceof Error ? err.message : String(err);
    const stack   = err instanceof Error ? err.stack  : undefined;
    await logEvent('error', source, message, { ...meta, ...(stack ? { stack: stack.slice(0, 1000) } : {}) });
}

/**
 * Log a critical error — triggers push notification (rate-limited).
 * @param {string} source
 * @param {Error|string} err
 * @param {object} [meta]
 */
async function logCritical(source, err, meta = {}) {
    const message = err instanceof Error ? err.message : String(err);
    const stack   = err instanceof Error ? err.stack  : undefined;
    await logEvent('critical', source, message, { ...meta, ...(stack ? { stack: stack.slice(0, 1000) } : {}) });
}

module.exports = { init, logEvent, logError, logCritical };
