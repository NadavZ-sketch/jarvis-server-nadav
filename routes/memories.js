const express = require('express');
const { createMemoriesController } = require('../controllers/memoriesController');
const { createRepos } = require('../services/dataAccess');

function createMemoriesRouter(deps) {
  const { supabase } = deps;
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createMemoriesController({ repos });

  router.get('/', controller.list);
  router.post('/', controller.create);
  router.post('/confirm', controller.confirm);
  router.get('/pending', controller.pending);
  router.post('/:id/approve', controller.approve);
  router.put('/:id', controller.update);
  router.delete('/:id', controller.remove);
  router.post('/rebuild-from-chat', controller.rebuildFromChat);
  router.post('/recover-from-pinecone', controller.recoverFromPinecone);

  return router;
}

module.exports = { createMemoriesRouter };
