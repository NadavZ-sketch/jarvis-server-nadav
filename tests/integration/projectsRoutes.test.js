'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));
jest.mock('../../agents/projectAgent', () => ({
  buildProjectsBriefing: jest.fn(async () => ({ briefing: 'ok' })),
}));

const express = require('express');
const request = require('supertest');
const { callGemma4 } = require('../../agents/models');
const { buildProjectsBriefing } = require('../../agents/projectAgent');
const { createProjectsRouter } = require('../../routes/projects');
const { makeRepos } = require('../helpers/fakeRepos');

function mountApp(repos) {
  const app = express();
  app.use(express.json());
  app.use('/projects', createProjectsRouter({ repos }));
  return app;
}

beforeEach(() => jest.clearAllMocks());

describe('GET /projects', () => {
  test('lists projects enriched with task/milestone progress', async () => {
    const repos = makeRepos({ projects: [{ id: 'p1', name: 'Demo' }] });
    repos.projects.countsForProjects = jest.fn(async () => ({
      tasks: [{ project_id: 'p1', done: true }, { project_id: 'p1', done: false }],
      milestones: [{ project_id: 'p1', completed: true }],
    }));

    const res = await request(mountApp(repos)).get('/projects');

    expect(res.status).toBe(200);
    expect(res.body.projects[0]).toMatchObject({ open_tasks: 1, total_tasks: 2, milestones_done: 1 });
  });
});

describe('POST /projects', () => {
  test('rejects missing name', async () => {
    const res = await request(mountApp(makeRepos())).post('/projects').send({});
    expect(res.status).toBe(400);
  });

  test('creates a project with defaults', async () => {
    const repos = makeRepos();
    const res = await request(mountApp(repos)).post('/projects').send({ name: 'New Project' });
    expect(res.status).toBe(200);
    expect(repos.projects.create).toHaveBeenCalledWith(expect.objectContaining({ name: 'New Project', status: 'active', methodology: 'kanban' }));
  });
});

describe('GET /projects/briefing', () => {
  test('is matched before /:id and delegates to buildProjectsBriefing', async () => {
    const repos = makeRepos();
    const res = await request(mountApp(repos)).get('/projects/briefing');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ briefing: 'ok' });
    expect(buildProjectsBriefing).toHaveBeenCalledWith(repos.projects, 'נדב');
  });
});

describe('GET /projects/:id', () => {
  test('404s when project not found', async () => {
    const res = await request(mountApp(makeRepos())).get('/projects/missing');
    expect(res.status).toBe(404);
  });
});

describe('Sprints', () => {
  test('POST /:id/sprints requires name/start_date/end_date', async () => {
    const res = await request(mountApp(makeRepos())).post('/projects/p1/sprints').send({});
    expect(res.status).toBe(400);
  });

  test('POST /:id/sprints/:sId/start conflicts when another sprint is active', async () => {
    const repos = makeRepos();
    repos.sprints.activeOthers = jest.fn(async () => [{ id: 'sp2' }]);
    const res = await request(mountApp(repos)).post('/projects/p1/sprints/sp1/start');
    expect(res.status).toBe(409);
  });

  test('POST /:id/sprints/:sId/complete releases tasks then marks completed', async () => {
    const repos = makeRepos();
    const res = await request(mountApp(repos)).post('/projects/p1/sprints/sp1/complete');
    expect(res.status).toBe(200);
    expect(repos.sprints.releaseTasks).toHaveBeenCalledWith('sp1');
    expect(repos.sprints.updateScoped).toHaveBeenCalledWith('sp1', 'p1', expect.objectContaining({ status: 'completed' }));
  });
});

describe('POST /projects/recommend-methodology', () => {
  test('parses the LLM JSON response and caches it', async () => {
    callGemma4.mockResolvedValue('{"methodology":"Scrum","reason":"team size"}');
    const app = mountApp(makeRepos());

    const first = await request(app).post('/projects/recommend-methodology').send({ name: 'X', description: 'Y' });
    expect(first.status).toBe(200);
    expect(first.body).toMatchObject({ methodology: 'scrum', reason: 'team size', cached: false });

    const second = await request(app).post('/projects/recommend-methodology').send({ name: 'X', description: 'Y' });
    expect(second.body.cached).toBe(true);
    expect(callGemma4).toHaveBeenCalledTimes(1);
  });
});
