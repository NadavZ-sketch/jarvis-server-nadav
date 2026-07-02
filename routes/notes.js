const express = require('express');
const { createNotesController } = require('../controllers/notesController');
const { createRepos } = require('../services/dataAccess');

function createNotesRouter(deps) {
  const { supabase } = deps;
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createNotesController({ repos });

  router.get('/',       controller.list);
  router.post('/',      controller.create);
  router.put('/:id',    controller.update);
  router.delete('/:id', controller.remove);

  return router;
}

module.exports = { createNotesRouter };
