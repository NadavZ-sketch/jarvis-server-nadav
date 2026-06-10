'use strict';

/**
 * Transport-swappable push notification service.
 *
 * Set PUSH_DRIVER env var to choose the delivery mechanism:
 *   'fcm'  — Firebase Cloud Messaging (requires FIREBASE_SERVICE_ACCOUNT_JSON)
 *   'ntfy' — ntfy.sh self-hosted or cloud (requires NTFY_TOPIC)
 *   'none' — no-op (default when env var is unset)
 *
 * The server side only knows about sendPush(); callers never import firebase-admin
 * or any transport directly. Swapping transports is a one-line env change.
 */

const driver = (process.env.PUSH_DRIVER || 'none').toLowerCase();

// ─── Device token store ───────────────────────────────────────────────────────
// Supabase client is injected via init() so this module stays testable.
let _supabase = null;

function init(supabaseClient) {
    _supabase = supabaseClient;
}

/** Upsert a device token (called from POST /push/register-token). */
async function registerToken({ token, platform = 'android', appVersion = '' }) {
    if (!_supabase) return;
    await _supabase.from('device_tokens').upsert(
        { token, platform, app_version: appVersion, last_seen: new Date().toISOString() },
        { onConflict: 'token' }
    );
}

/** Fetch all stored FCM tokens. */
async function _getTokens() {
    if (!_supabase) return [];
    const { data } = await _supabase.from('device_tokens').select('token, platform');
    return data || [];
}

// ─── FCM driver ───────────────────────────────────────────────────────────────
let _fcmApp = null;

function _initFCM() {
    if (_fcmApp) return _fcmApp;
    if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
        console.warn('[push] FCM: FIREBASE_SERVICE_ACCOUNT_JSON not set — driver disabled');
        return null;
    }
    try {
        const admin = require('firebase-admin');
        if (!admin.apps.length) {
            const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
            admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
        }
        _fcmApp = admin;
        console.log('[push] FCM driver initialized');
        return _fcmApp;
    } catch (err) {
        console.error('[push] FCM init error:', err.message);
        return null;
    }
}

async function _sendFCM({ title, body, data = {} }) {
    const admin = _initFCM();
    if (!admin) return;

    const tokens = await _getTokens();
    if (tokens.length === 0) {
        console.log('[push] FCM: no registered tokens');
        return;
    }

    const tokenStrings = tokens.map(t => t.token);
    const message = {
        notification: { title, body },
        data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
        android: { priority: 'high', notification: { channelId: 'jarvis_alerts', sound: 'default' } },
        tokens: tokenStrings,
    };

    try {
        const response = await admin.messaging().sendEachForMulticast(message);
        // Prune stale tokens
        const staleTokens = [];
        response.responses.forEach((r, i) => {
            if (!r.success && r.error?.code === 'messaging/registration-token-not-registered') {
                staleTokens.push(tokenStrings[i]);
            }
        });
        if (staleTokens.length > 0 && _supabase) {
            await _supabase.from('device_tokens').delete().in('token', staleTokens);
            console.log(`[push] FCM: pruned ${staleTokens.length} stale token(s)`);
        }
        console.log(`[push] FCM: sent to ${response.successCount}/${tokenStrings.length} devices`);
    } catch (err) {
        console.error('[push] FCM send error:', err.message);
    }
}

// ─── ntfy driver ─────────────────────────────────────────────────────────────
async function _sendNtfy({ title, body }) {
    const topic = process.env.NTFY_TOPIC;
    if (!topic) {
        console.warn('[push] ntfy: NTFY_TOPIC not set');
        return;
    }
    try {
        const axios = require('axios');
        await axios.post(`https://ntfy.sh/${topic}`, body, {
            headers: {
                Title: title,
                Priority: 'high',
                Tags: 'jarvis',
                'Content-Type': 'text/plain; charset=utf-8',
            },
            timeout: 5000,
        });
        console.log('[push] ntfy: sent');
    } catch (err) {
        console.error('[push] ntfy send error:', err.message);
    }
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Send a push notification.
 * @param {object} opts
 * @param {string} opts.title   - Hebrew notification title
 * @param {string} opts.body    - Notification body text
 * @param {object} [opts.data]  - Optional key/value payload (FCM data fields)
 * @param {string} [opts.category] - Category hint ('proactive'|'alert'|'reminder')
 */
async function sendPush({ title = 'ג׳רביס 🤖', body, data = {}, category = 'proactive' } = {}) {
    if (!body) return;
    try {
        if (driver === 'fcm') {
            await _sendFCM({ title, body, data: { ...data, category } });
        } else if (driver === 'ntfy') {
            await _sendNtfy({ title, body });
        }
        // 'none' is a documented no-op
    } catch (err) {
        console.error('[push] sendPush error:', err.message);
    }
}

module.exports = { init, registerToken, sendPush };
