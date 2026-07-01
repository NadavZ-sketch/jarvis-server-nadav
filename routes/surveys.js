const express = require('express');
const { createSurveysController } = require('../controllers/surveysController');
const { createRepos } = require('../services/dataAccess');
const agentMetrics = require('../services/agentMetrics');

// Mounted at '/' (like routes/chat.js) — paths mix /surveys/* (nested) and
// /survey-* (flat, hyphenated), so there's no single prefix to mount under.
function createSurveysRouter(deps) {
  const { supabase, _rl } = deps;
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createSurveysController({ repos, agentMetrics });
  const rl = _rl || (() => (_req, _res, next) => next());

  router.get('/surveys/export', rl(5), controller.exportCsv);
  router.post('/surveys/analyze-sentiment', rl(10), controller.analyzeSentiment);

  router.get('/survey-check', controller.check);
  router.post('/survey-submit', controller.submit);
  router.get('/survey-history', controller.history);
  router.get('/survey-insights', controller.insights);
  router.get('/survey-smart-check', controller.smartCheck);
  router.get('/survey-impact', controller.impact);

  return router;
}

module.exports = { createSurveysRouter };
