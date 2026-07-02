const express = require('express');
const { createContactsController } = require('../controllers/contactsController');
const { createRepos } = require('../services/dataAccess');

function createContactsRouter(deps) {
  const { supabase } = deps;
  const repos = deps.repos || createRepos(supabase);
  // Policy middleware is injected by server.js; default to a pass-through so
  // the router stays constructible in isolation (unit/integration tests).
  const requirePolicy = deps.requirePolicy || (() => (_req, _res, next) => next());
  const router = express.Router();
  const controller = createContactsController({ repos });

  router.get('/',       requirePolicy('contacts.read', {}), controller.list);
  router.post('/',      requirePolicy('contacts.create', {}), controller.create);
  router.put('/:id',    requirePolicy('contacts.update', {}), controller.update);
  router.delete('/:id', requirePolicy('contacts.delete', { sensitive: true, irreversible: true }), controller.remove);

  return router;
}

module.exports = { createContactsRouter };
