const express = require('express');
const { createDashboardFeaturesController } = require('../controllers/dashboardFeaturesController');

function createDashboardFeaturesRouter() {
  const router = express.Router();
  const controller = createDashboardFeaturesController();

  router.get('/',    controller.list);
  router.patch('/',  controller.move);
  router.post('/',   controller.create);
  router.delete('/', controller.remove);
  router.post('/suggest-description', controller.suggestDescription);
  router.post('/generate-descriptions', controller.generateDescriptions);

  return router;
}

module.exports = { createDashboardFeaturesRouter };
