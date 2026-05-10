const express = require('express');
const { createChatController } = require('../controllers/chatController');

function createChatRouter(deps) {
  const router = express.Router();
  const controller = createChatController(deps);

  router.post('/ask-jarvis', controller.askJarvis);
  router.post('/stream-jarvis', controller.streamJarvis);
  router.get('/chat-history', controller.getChatHistory);

  return router;
}

module.exports = { createChatRouter };
