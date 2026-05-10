const express = require('express');
const { createRemindersController } = require('../controllers/remindersController');

function createRemindersRouter(deps) {
  const router = express.Router();
  const controller = createRemindersController(deps);

  router.get('/', controller.list);
  router.post('/', controller.create);
  router.put('/:id', controller.update);
  router.delete('/:id', controller.remove);
  router.get('/check', controller.check);

  return router;
}

module.exports = { createRemindersRouter };
