'use strict';

// Cron-run repository — data-access seam for the `cron_runs` table that tracks
// each scheduled job's last success/error. Writes are fire-and-forget (callers
// attach .then(null, …)); the builder is returned as-is to preserve that.

const C = 'cron_runs';

function createCronRepo(supabase) {
    return {
        markOk(jobName) {
            return supabase.from(C).upsert(
                { job_name: jobName, last_ok_at: new Date().toISOString() },
                { onConflict: 'job_name' },
            );
        },

        markError(jobName, message) {
            return supabase.from(C).upsert(
                { job_name: jobName, last_err_at: new Date().toISOString(), last_error: (message || '').slice(0, 500) },
                { onConflict: 'job_name' },
            );
        },

        async lastOkAt(jobName) {
            const { data } = await supabase.from(C)
                .select('last_ok_at')
                .eq('job_name', jobName)
                .maybeSingle();
            return data?.last_ok_at || null;
        },
    };
}

module.exports = { createCronRepo };
