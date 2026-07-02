const express = require('express');
const { createRouterTrainerController } = require('../controllers/routerTrainerController');

function createRouterTrainerRouter(deps) {
  const { supabase, _rl } = deps;
  const router = express.Router();
  const controller = createRouterTrainerController({ supabase });
  const rl = _rl || (() => (_req, _res, next) => next());

  router.get('/training-events', rl(30), controller.trainingEvents);
  router.get('/misroutes', rl(30), controller.misroutes);
  router.get('/keywords', rl(30), controller.getKeywords);
  router.post('/keywords', rl(20), controller.postKeywords);
  router.delete('/keywords', rl(20), controller.deleteKeywords);

  return router;
}

module.exports = { createRouterTrainerRouter };
