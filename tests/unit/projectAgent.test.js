const { runProjectAgent } = require('../../agents/projectAgent');
jest.mock('../../agents/models');
const { callGemma4 } = require('../../agents/models');
const { makeProjectRepo } = require('../helpers/fakeRepos');

const reposWith = (opts) => ({ projects: makeProjectRepo(opts) });

describe('projectAgent — create', () => {
    it('inserts a new project and returns confirmation', async () => {
        const newProject = { id: 'uuid-1', name: 'אפליקציה', status: 'active', priority: 'high', color: '#6366f1' };
        const repos = reposWith({ createResult: { data: newProject, error: null } });
        callGemma4.mockResolvedValue(JSON.stringify({
            intent: 'create', projectName: 'אפליקציה', description: 'אפליקציה חדשה',
            priority: 'high', dueDate: '2026-12-31', status: 'active', color: null,
        }));
        const result = await runProjectAgent('צור פרויקט אפליקציה', repos, false, { userName: 'נדב' });
        expect(result.answer).toContain('אפליקציה');
        expect(repos.projects.create).toHaveBeenCalled();
    });

    it('returns error if no project name given', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'create', projectName: '', description: '' }));
        const result = await runProjectAgent('צור פרויקט', reposWith({}), false);
        expect(result.answer).toContain('שם');
    });
});

describe('projectAgent — list', () => {
    it('returns formatted list when projects exist', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list', projectName: '' }));
        const repos = reposWith({ projects: [
            { id: '1', name: 'פרויקט A', status: 'active', priority: 'high', due_date: '2026-12-31' },
            { id: '2', name: 'פרויקט B', status: 'completed', priority: 'low', due_date: null },
        ] });
        const result = await runProjectAgent('הצג פרויקטים', repos, false, { userName: 'נדב' });
        expect(result.answer).toContain('פרויקט A');
        expect(result.answer).toContain('פרויקט B');
    });

    it('returns empty message when no projects', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list', projectName: '' }));
        const result = await runProjectAgent('הפרויקטים שלי', reposWith({ projects: [] }), false, { userName: 'נדב' });
        expect(result.answer).toContain('אין לך פרויקטים');
    });
});

describe('projectAgent — add_task', () => {
    it('inserts task linked to project', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({
            intent: 'add_task', projectName: 'אפליקציה', taskText: 'לכתוב unit tests', priority: 'high', dueDate: null,
        }));
        const repos = reposWith({ projects: [{ id: 'proj-1', name: 'אפליקציה' }] });
        const result = await runProjectAgent('הוסף משימה לפרויקט אפליקציה: לכתוב unit tests', repos, false);
        expect(result.answer).toContain('לכתוב unit tests');
        expect(repos.projects.addTask).toHaveBeenCalledWith(
            expect.objectContaining({ content: 'לכתוב unit tests', project_id: 'proj-1' })
        );
    });
});

describe('projectAgent — add_milestone', () => {
    it('inserts milestone linked to project', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({
            intent: 'add_milestone', projectName: 'אפליקציה', milestoneText: 'גרסה ראשונה', milestoneDue: '2026-09-01',
        }));
        const repos = reposWith({ projects: [{ id: 'proj-1', name: 'אפליקציה' }] });
        const result = await runProjectAgent('הוסף אבן דרך לפרויקט אפליקציה: גרסה ראשונה', repos, false);
        expect(result.answer).toContain('גרסה ראשונה');
        expect(repos.projects.addMilestone).toHaveBeenCalledWith(
            expect.objectContaining({ title: 'גרסה ראשונה', project_id: 'proj-1' })
        );
    });
});

describe('projectAgent — insight', () => {
    it('returns insights for active projects', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'insight', projectName: '' }));
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        const repos = reposWith({ projects: [
            { id: 'p1', name: 'פרויקט בזמן', status: 'active', priority: 'high', due_date: null },
            { id: 'p2', name: 'פרויקט שחרג', status: 'active', priority: 'critical', due_date: yesterday.toISOString().split('T')[0] },
        ] });
        const result = await runProjectAgent('תובנות פרויקטים', repos, false);
        expect(result.answer).toContain('תובנות');
        expect(result.answer).toContain('פרויקט שחרג');
    });
});

describe('projectAgent — delete', () => {
    it('deletes project when found', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'delete', projectName: 'ישן' }));
        const repos = reposWith({ projects: [{ id: 'del-1', name: 'ישן' }] });
        const result = await runProjectAgent('מחק פרויקט ישן', repos, false);
        expect(result.answer).toContain('ישן');
        expect(repos.projects.remove).toHaveBeenCalledWith('del-1');
    });
});

describe('projectAgent — error handling', () => {
    it('returns fallback if LLM returns no JSON', async () => {
        callGemma4.mockResolvedValue('אני לא מבין');
        const result = await runProjectAgent('בלה בלה', reposWith({}), false);
        expect(typeof result.answer).toBe('string');
        expect(result.answer).toBeTruthy();
    });

    it('returns fallback on a repo error', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list', projectName: '' }));
        const repos = reposWith({});
        repos.projects.listNonArchived = jest.fn().mockRejectedValue(new Error('DB down'));
        const result = await runProjectAgent('הצג פרויקטים', repos, false);
        expect(result.answer).toBeTruthy();
    });
});
