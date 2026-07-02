const express = require('express');
const { createShoppingController } = require('../controllers/shoppingController');
const { createRepos } = require('../services/dataAccess');

function createShoppingRouter(deps) {
  const { supabase } = deps;
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createShoppingController({ repos });

  router.get('/',        controller.list);
  router.post('/',       controller.create);
  router.patch('/:id',   controller.update);
  router.delete('/:id',  controller.remove);

  return router;
}

module.exports = { createShoppingRouter };
