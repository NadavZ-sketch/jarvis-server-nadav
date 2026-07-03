const express = require('express');
const { createMemoriesController } = require('../controllers/memoriesController');
const { createRepos } = require('../services/dataAccess');

function createMemoriesRouter(deps) {
  const { supabase } = deps;
  const repos = deps.repos || createRepos(supabase);
  // Policy middleware is injected by server.js; default to a pass-through so
  // the router stays constructible in isolation (unit tests).
  const requirePolicy = deps.requirePolicy || (() => (_req, _res, next) => next());
  const router = express.Router();
  const controller = createMemoriesController({ repos });

  router.get('/', controller.list);
  router.post('/', controller.create);
  router.post('/confirm', controller.confirm);
  router.get('/pending', controller.pending);
  router.get('/health/findings', controller.listHealthFindings);
  router.post('/health/run', controller.runHealthScan);
  router.post('/health/findings/:id/resolve', requirePolicy('memory.delete', { sensitive: true, irreversible: true }), controller.resolveHealthFinding);
  router.post('/health/findings/:id/dismiss', controller.dismissHealthFinding);
  router.post('/:id/approve', controller.approve);
  router.put('/:id', controller.update);
  router.delete('/:id', requirePolicy('memory.delete', { sensitive: true, irreversible: true }), controller.remove);
  router.post('/rebuild-from-chat', controller.rebuildFromChat);
  router.post('/recover-from-pinecone', controller.recoverFromPinecone);

  return router;
}

module.exports = { createMemoriesRouter };
