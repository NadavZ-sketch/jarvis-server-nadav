const express = require('express');
const { createTasksController } = require('../controllers/tasksController');

function createTasksRouter(deps) {
  const router = express.Router();
  const controller = createTasksController(deps);

  router.get('/', controller.list);
  router.post('/', controller.create);
  router.put('/:id', controller.update);
  router.delete('/:id', controller.remove);

  return router;
}

module.exports = { createTasksRouter };
