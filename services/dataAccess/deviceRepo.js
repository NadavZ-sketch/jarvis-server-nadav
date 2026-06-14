'use strict';

// Device-token repository — data-access seam for the `device_tokens` table
// (push registration + stale-token pruning).

const D = 'device_tokens';

function createDeviceRepo(supabase) {
    return {
        upsertToken(row) {
            return supabase.from(D).upsert(row, { onConflict: 'token' });
        },

        async list() {
            const { data } = await supabase.from(D).select('token, platform');
            return data || [];
        },

        deleteTokens(tokens) {
            return supabase.from(D).delete().in('token', tokens);
        },
    };
}

module.exports = { createDeviceRepo };
