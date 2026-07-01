const express = require('express');
const { createCalendarController } = require('../controllers/calendarController');
const { createRepos } = require('../services/dataAccess');

// Mounted at '/' (like routes/chat.js) — /auth/google/*, /calendar-events, and
// /upcoming-items don't share a single path prefix.
function createCalendarRouter(deps) {
  const { supabase, cacheInvalidate } = deps;
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createCalendarController({ repos, cacheInvalidate });

  router.get('/auth/google/start', controller.authStart);
  router.get('/auth/google/callback', controller.authCallback);
  router.get('/calendar-events', controller.events);
  router.get('/upcoming-items', controller.upcomingItems);

  return router;
}

module.exports = { createCalendarRouter };
