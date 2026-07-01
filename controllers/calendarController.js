const crypto = require('crypto');
const axios = require('axios');
const { buildAuthUrl } = require('../agents/calendarAgent');

// Short-lived nonces for CSRF protection on the OAuth flow (TTL: 10 min).
const _oauthNonces = new Map(); // nonce -> expiresAt
const _OAUTH_NONCE_TTL = 10 * 60 * 1000;

function createCalendarController({ repos, cacheInvalidate }) {
  return {
    authStart(_req, res) {
      if (!process.env.GOOGLE_CLIENT_ID || !process.env.GOOGLE_CLIENT_SECRET) {
        return res.status(400).json({ error: 'GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET not configured' });
      }
      const state = crypto.randomBytes(32).toString('hex');
      _oauthNonces.set(state, Date.now() + _OAUTH_NONCE_TTL);
      const redirectUri = `${process.env.SERVER_URL || `http://localhost:${process.env.PORT || 3000}`}/auth/google/callback`;
      const authUrl = buildAuthUrl(redirectUri, state);
      res.redirect(authUrl);
    },

    async authCallback(req, res) {
      const { code, error, state } = req.query;
      if (error) return res.status(400).send('OAuth error');
      if (!code) return res.status(400).send('No code received');

      const nonceExpiry = _oauthNonces.get(state);
      if (!nonceExpiry || Date.now() > nonceExpiry) {
        return res.status(400).send('Invalid or expired OAuth state');
      }
      _oauthNonces.delete(state);

      try {
        const redirectUri = `${process.env.SERVER_URL || `http://localhost:${process.env.PORT || 3000}`}/auth/google/callback`;
        const tokenRes = await axios.post('https://oauth2.googleapis.com/token', {
          client_id: process.env.GOOGLE_CLIENT_ID,
          client_secret: process.env.GOOGLE_CLIENT_SECRET,
          code,
          grant_type: 'authorization_code',
          redirect_uri: redirectUri,
        });
        const tokenData = tokenRes.data;
        // Store refresh token in user_profiles
        await repos.profile.saveCalendarToken(JSON.stringify(tokenData));
        cacheInvalidate('userProfile');
        res.send('<h2>✅ יומן Google חובר בהצלחה! אפשר לסגור את החלון.</h2>');
      } catch (err) {
        console.error('Google OAuth callback error:', err.message);
        res.status(500).send('OAuth failed');
      }
    },

    async events(_req, res) {
      try {
        const [taskRows, reminderRows] = await Promise.all([
          repos.tasks.datedAll(),
          repos.reminders.allOrdered(),
        ]);

        const formatDate = (dateStr) => {
          if (!dateStr) return null;
          try {
            const d = new Date(dateStr);
            return d.toISOString();
          } catch {
            return null;
          }
        };

        const tasks = (taskRows || [])
          .filter(t => formatDate(t.due_date))
          .map(t => ({
            id:    `task-${t.id}`,
            type:  'task',
            title: t.content || 'משימה ללא כותרת',
            date:  formatDate(t.due_date),
            done:  t.done === true,
          }));

        const reminders = (reminderRows || [])
          .filter(r => formatDate(r.scheduled_time))
          .map(r => ({
            id:    `reminder-${r.id}`,
            type:  'reminder',
            title: r.text || 'תזכורת ללא טקסט',
            date:  formatDate(r.scheduled_time),
            done:  r.fired === true,
          }));

        const events = [...tasks, ...reminders];
        console.log(`📅 Calendar: returning ${events.length} events (${tasks.length} tasks, ${reminders.length} reminders)`);
        res.json({ events });
      } catch (err) {
        console.error('GET /calendar-events error:', err.message);
        res.status(500).json({ events: [] });
      }
    },

    // Upcoming tasks/reminders (for proactive suggestions)
    async upcomingItems(_req, res) {
      try {
        const now = new Date();
        const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);

        const [taskRows, reminderRows] = await Promise.all([
          repos.tasks.upcomingDated(now.toISOString(), tomorrow.toISOString(), 5),
          repos.reminders.upcomingUnfired(now.toISOString(), tomorrow.toISOString(), 5),
        ]);

        const upcoming = [
          ...(taskRows || []).map(t => ({
            type: 'task',
            title: t.content,
            date: t.due_date,
          })),
          ...(reminderRows || []).map(r => ({
            type: 'reminder',
            title: r.text,
            date: r.scheduled_time,
          })),
        ].sort((a, b) => new Date(a.date) - new Date(b.date));

        res.json({ upcoming });
      } catch (err) {
        console.error('GET /upcoming-items error:', err.message);
        res.status(500).json({ upcoming: [] });
      }
    },
  };
}

module.exports = { createCalendarController };
