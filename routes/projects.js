const express = require('express');
const { createProjectsController } = require('../controllers/projectsController');
const { createRepos } = require('../services/dataAccess');

function createProjectsRouter(deps) {
  const { supabase } = deps;
  const repos = deps.repos || createRepos(supabase);
  const router = express.Router();
  const controller = createProjectsController({ repos });

  router.get('/', controller.list);
  router.post('/', controller.create);

  // Deterministic weekly briefing (zero LLM tokens). Must be registered before
  // GET /:id so the ":id" param doesn't capture "briefing".
  router.get('/briefing', controller.briefing);

  router.get('/:id', controller.getById);
  router.put('/:id', controller.update);
  router.delete('/:id', controller.remove);

  router.get('/:id/milestones', controller.listMilestones);
  router.post('/:id/milestones', controller.createMilestone);
  router.put('/:id/milestones/:mId', controller.updateMilestone);
  router.delete('/:id/milestones/:mId', controller.removeMilestone);

  // ─── Project Sprints (Scrum) ──────────────────────────────────────────────
  router.get('/:id/sprints', controller.listSprints);
  router.post('/:id/sprints', controller.createSprint);
  router.put('/:id/sprints/:sId', controller.updateSprint);
  router.delete('/:id/sprints/:sId', controller.removeSprint);
  router.post('/:id/sprints/:sId/start', controller.startSprint);
  router.post('/:id/sprints/:sId/complete', controller.completeSprint);

  // ─── Methodology recommendation + AI insights (cached) ─────────────────────
  router.post('/recommend-methodology', controller.recommendMethodology);
  router.post('/:id/ai-insights', controller.aiInsights);

  return router;
}

module.exports = { createProjectsRouter };
