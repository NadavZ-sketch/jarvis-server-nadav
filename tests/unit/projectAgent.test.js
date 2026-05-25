const { runProjectAgent } = require('../../agents/projectAgent');
jest.mock('../../agents/models');
const { callGemma4 } = require('../../agents/models');

function makeSupabase(overrides = {}) {
    const chain = {
        select: jest.fn().mockReturnThis(),
        insert: jest.fn().mockReturnThis(),
        update: jest.fn().mockReturnThis(),
        delete: jest.fn().mockReturnThis(),
        eq: jest.fn().mockReturnThis(),
        ilike: jest.fn().mockReturnThis(),
        not: jest.fn().mockReturnThis(),
        in: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
        order: jest.fn().mockReturnThis(),
        single: jest.fn().mockResolvedValue({ data: null, error: null }),
        ...overrides,
    };
    return { from: jest.fn(() => chain), _chain: chain };
}

describe('projectAgent — create', () => {
    it('inserts a new project and returns confirmation', async () => {
        const newProject = { id: 'uuid-1', name: 'אפליקציה', status: 'active', priority: 'high', color: '#6366f1' };
        const sb = makeSupabase();
        sb._chain.single.mockResolvedValue({ data: newProject, error: null });

        callGemma4.mockResolvedValue(JSON.stringify({
            intent: 'create',
            projectName: 'אפליקציה',
            description: 'אפליקציה חדשה',
            priority: 'high',
            dueDate: '2026-12-31',
            status: 'active',
            color: null,
        }));

        const result = await runProjectAgent('צור פרויקט אפליקציה', sb, false, { userName: 'נדב' });
        expect(result.answer).toContain('אפליקציה');
        expect(sb.from).toHaveBeenCalledWith('projects');
        expect(sb._chain.insert).toHaveBeenCalled();
    });

    it('returns error if no project name given', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'create', projectName: '', description: '' }));
        const sb = makeSupabase();
        const result = await runProjectAgent('צור פרויקט', sb, false);
        expect(result.answer).toContain('שם');
    });
});

describe('projectAgent — list', () => {
    it('returns formatted list when projects exist', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list', projectName: '' }));
        const sb = makeSupabase();
        sb._chain.order = jest.fn().mockResolvedValue({
            data: [
                { id: '1', name: 'פרויקט A', status: 'active', priority: 'high', due_date: '2026-12-31' },
                { id: '2', name: 'פרויקט B', status: 'completed', priority: 'low', due_date: null },
            ],
            error: null,
        });

        const result = await runProjectAgent('הצג פרויקטים', sb, false, { userName: 'נדב' });
        expect(result.answer).toContain('פרויקט A');
        expect(result.answer).toContain('פרויקט B');
    });

    it('returns empty message when no projects', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list', projectName: '' }));
        const sb = makeSupabase();
        sb._chain.order = jest.fn().mockResolvedValue({ data: [], error: null });
        const result = await runProjectAgent('הפרויקטים שלי', sb, false, { userName: 'נדב' });
        expect(result.answer).toContain('אין לך פרויקטים');
    });
});

describe('projectAgent — add_task', () => {
    it('inserts task linked to project', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({
            intent: 'add_task',
            projectName: 'אפליקציה',
            taskText: 'לכתוב unit tests',
            priority: 'high',
            dueDate: null,
        }));
        const sb = makeSupabase();
        sb._chain.ilike = jest.fn().mockReturnThis();
        sb._chain.limit = jest.fn().mockResolvedValue({
            data: [{ id: 'proj-1', name: 'אפליקציה' }],
            error: null,
        });
        sb._chain.single.mockResolvedValue({ data: { id: 'task-1' }, error: null });

        const result = await runProjectAgent('הוסף משימה לפרויקט אפליקציה: לכתוב unit tests', sb, false);
        expect(result.answer).toContain('לכתוב unit tests');
        expect(sb.from).toHaveBeenCalledWith('tasks');
    });
});

describe('projectAgent — add_milestone', () => {
    it('inserts milestone linked to project', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({
            intent: 'add_milestone',
            projectName: 'אפליקציה',
            milestoneText: 'גרסה ראשונה',
            milestoneDue: '2026-09-01',
        }));
        const sb = makeSupabase();
        sb._chain.limit = jest.fn().mockResolvedValue({
            data: [{ id: 'proj-1', name: 'אפליקציה' }],
            error: null,
        });
        sb._chain.single.mockResolvedValue({ data: { id: 'ms-1' }, error: null });

        const result = await runProjectAgent('הוסף אבן דרך לפרויקט אפליקציה: גרסה ראשונה', sb, false);
        expect(result.answer).toContain('גרסה ראשונה');
        expect(sb.from).toHaveBeenCalledWith('project_milestones');
    });
});

describe('projectAgent — insight', () => {
    it('returns insights for active projects', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'insight', projectName: '' }));
        const sb = makeSupabase();

        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        const projects = [
            { id: 'p1', name: 'פרויקט בזמן', status: 'active', priority: 'high', due_date: null },
            { id: 'p2', name: 'פרויקט שחרג', status: 'active', priority: 'critical', due_date: yesterday.toISOString().split('T')[0] },
        ];

        // .from('projects').select('*').eq('status','active') → resolves with projects
        sb._chain.eq = jest.fn().mockResolvedValue({ data: projects, error: null });
        // computeProgress calls: .from('tasks').select('done').eq('project_id',id)
        //                        .from('project_milestones').select('completed').eq('project_id',id)
        // Both resolve with empty arrays (progress=0)

        const result = await runProjectAgent('תובנות פרויקטים', sb, false);
        expect(result.answer).toContain('תובנות');
        expect(result.answer).toContain('פרויקט שחרג');
    });
});

describe('projectAgent — delete', () => {
    it('deletes project when found', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'delete', projectName: 'ישן' }));
        const sb = makeSupabase();
        sb._chain.limit = jest.fn().mockResolvedValue({
            data: [{ id: 'del-1', name: 'ישן' }],
            error: null,
        });
        sb._chain.eq = jest.fn().mockResolvedValue({ error: null });

        const result = await runProjectAgent('מחק פרויקט ישן', sb, false);
        expect(result.answer).toContain('ישן');
        expect(sb.from).toHaveBeenCalledWith('projects');
    });
});

describe('projectAgent — error handling', () => {
    it('returns fallback if LLM returns no JSON', async () => {
        callGemma4.mockResolvedValue('אני לא מבין');
        const sb = makeSupabase();
        const result = await runProjectAgent('בלה בלה', sb, false);
        expect(result.answer).toBeTruthy();
        expect(typeof result.answer).toBe('string');
    });

    it('returns fallback on supabase error', async () => {
        callGemma4.mockResolvedValue(JSON.stringify({ intent: 'list', projectName: '' }));
        const sb = makeSupabase();
        sb._chain.order = jest.fn().mockRejectedValue(new Error('DB down'));
        const result = await runProjectAgent('הצג פרויקטים', sb, false);
        expect(result.answer).toBeTruthy();
    });
});
