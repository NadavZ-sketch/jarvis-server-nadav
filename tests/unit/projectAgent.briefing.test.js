'use strict';

jest.mock('../../agents/models', () => ({ callGemma4: jest.fn() }));

const { buildProjectsBriefing } = require('../../agents/projectAgent');
const { makeProjectRepo } = require('../helpers/fakeRepos');

describe('buildProjectsBriefing', () => {
  test('no active projects → prompt to create one', async () => {
    const repo = makeProjectRepo({ projects: [] });
    const res = await buildProjectsBriefing(repo, 'דני');
    expect(res.answer).toContain('אין פרויקטים פעילים');
    expect(res.answer).toContain('דני');
    expect(res.action).toBeUndefined();
  });

  test('active project renders a progress bar, percentage, and navigate action', async () => {
    const repo = makeProjectRepo({
      projects: [{ id: 1, name: 'אפליקציית כושר', status: 'active', priority: 'high', due_date: null }],
      taskDone: [{ done: true }, { done: false }],   // 1 of 2 done
      milestoneCompleted: [],
    });
    const res = await buildProjectsBriefing(repo);
    expect(res.answer).toContain('אפליקציית כושר');
    expect(res.answer).toContain('50%');
    expect(res.answer).toMatch(/[█░]/);
    expect(res.action).toEqual(expect.objectContaining({ type: 'navigate', target: 'projects' }));
  });

  test('overdue project is flagged as exceeded', async () => {
    const repo = makeProjectRepo({
      projects: [{ id: 2, name: 'אתר תדמית', status: 'active', priority: 'medium', due_date: '2000-01-01' }],
      taskDone: [{ done: true }],
      milestoneCompleted: [{ completed: true }],
    });
    const res = await buildProjectsBriefing(repo);
    expect(res.answer).toContain('אתר תדמית');
    expect(res.answer).toContain('100%');
    expect(res.answer).toContain('חרג');
  });
});
