const express = require('express');
const { createRemindersController } = require('../controllers/remindersController');

function createRemindersRouter(deps) {
  const router = express.Router();
  const controller = createRemindersController(deps);
  const policy = deps.requirePolicy || ((_a, _o) => (_req, _res, next) => next());

  router.get('/', policy('reminders.read', { sensitive: true }), controller.list);
  router.post('/', policy('reminders.create', { sensitive: true }), controller.create);
  router.put('/:id', policy('reminders.update', { sensitive: true }), controller.update);
  router.delete('/:id', policy('reminders.delete', { sensitive: true, irreversible: true }), controller.remove);
  router.get('/check', policy('reminders.read', { sensitive: true }), controller.check);

  return router;
}

module.exports = { createRemindersRouter };
