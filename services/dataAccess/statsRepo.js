'use strict';

// Stats repository — data-access seam for the cross-table dashboard count
// aggregates behind GET /stats. Read-only; never throws (per-count failures
// degrade to 0 via Promise.allSettled).

const HEAD = { count: 'exact', head: true };

function createStatsRepo(supabase) {
    return {
        async dashboardCounts(todayISO) {
            const [
                chatTotal, chatToday, tasksTotal, tasksDone,
                remindersTotal, remindersActive, memoriesTotal, notesTotal,
                shoppingTotal, shoppingChecked, pendingCategories,
            ] = await Promise.allSettled([
                supabase.from('chat_history').select('id', HEAD),
                supabase.from('chat_history').select('id', HEAD).gte('created_at', todayISO),
                supabase.from('tasks').select('id', HEAD),
                supabase.from('tasks').select('id', HEAD).eq('done', true),
                supabase.from('reminders').select('id', HEAD),
                supabase.from('reminders').select('id', HEAD).eq('fired', false),
                supabase.from('memories').select('id', HEAD),
                supabase.from('notes').select('id', HEAD),
                supabase.from('shopping_items').select('id', HEAD),
                supabase.from('shopping_items').select('id', HEAD).eq('checked', true),
                supabase.from('tasks').select('category').eq('done', false),
            ]);

            const getCount = (r) =>
                (r.status === 'fulfilled' && !r.value.error) ? (r.value.count ?? 0) : 0;

            const byCategory = { work: 0, personal: 0, financial: 0, project: 0, general: 0 };
            if (pendingCategories.status === 'fulfilled' && !pendingCategories.value.error) {
                for (const row of pendingCategories.value.data || []) {
                    const c = byCategory[row.category] !== undefined ? row.category : 'general';
                    byCategory[c]++;
                }
            }

            return {
                chat:      { total: getCount(chatTotal),      today:   getCount(chatToday) },
                tasks:     { total: getCount(tasksTotal),     done:    getCount(tasksDone),    pending: getCount(tasksTotal) - getCount(tasksDone), byCategory },
                reminders: { total: getCount(remindersTotal), active:  getCount(remindersActive) },
                memories:  { total: getCount(memoriesTotal) },
                notes:     { total: getCount(notesTotal) },
                shopping:  { total: getCount(shoppingTotal),  checked: getCount(shoppingChecked) },
            };
        },

        // Counts for GET /today-message (pending / yesterday completion / active reminders).
        async todayMessageCounts(yesterdayStartISO, todayStartISO) {
            const [pending, doneY, totalY, reminders] = await Promise.all([
                supabase.from('tasks').select('id', HEAD).eq('done', false),
                supabase.from('tasks').select('id', HEAD).eq('done', true).gte('created_at', yesterdayStartISO).lt('created_at', todayStartISO),
                supabase.from('tasks').select('id', HEAD).gte('created_at', yesterdayStartISO).lt('created_at', todayStartISO),
                supabase.from('reminders').select('id', HEAD).eq('fired', false),
            ]);
            return {
                pending:        pending.count        ?? 0,
                doneYesterday:  doneY.count          ?? 0,
                totalYesterday: totalY.count         ?? 0,
                reminders:      reminders.count      ?? 0,
            };
        },
    };
}

module.exports = { createStatsRepo };
