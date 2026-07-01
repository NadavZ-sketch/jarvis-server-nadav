const express = require('express');
const { createE2EController } = require('../controllers/e2eController');
const { createRepos } = require('../services/dataAccess');

// Mounted at '/' (like routes/chat.js) since the underlying paths don't share
// a single prefix: /e2e-reports/*, /e2e-schedule, /e2e/trigger.
function createE2ERouter(deps) {
  const { supabase, cacheInvalidate, _rl } = deps;
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createE2EController({ repos, supabase, cacheInvalidate });
  const rl = _rl || (() => (_req, _res, next) => next());

  router.get('/e2e-schedule', rl(20), controller.getSchedule);
  router.put('/e2e-schedule', rl(10), controller.putSchedule);

  router.get('/e2e-reports', controller.listReports);
  router.get('/e2e-reports/:runId', controller.getReport);
  router.delete('/e2e-reports/:runId', controller.deleteReport);
  router.post('/e2e-reports/:runId/prompt', controller.reportPrompt);
  router.post('/e2e-reports/:runId/mark-done', controller.markDone);

  router.post('/e2e/trigger', rl(3), controller.trigger);

  return router;
}

module.exports = { createE2ERouter };
