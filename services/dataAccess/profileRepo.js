'use strict';

// Profile repository — data-access seam for the `user_profiles` table. The
// local-file fallback, caching, and payload assembly stay in server.js.

const P = 'user_profiles';

function createProfileRepo(supabase) {
    return {
        // Most-recently-updated profile row; throws on error so the caller can
        // fall back to the local profile without caching a transient failure.
        async latest() {
            const { data, error } = await supabase.from(P)
                .select('*')
                .order('updated_at', { ascending: false })
                .limit(1);
            if (error) throw error;
            return data || [];
        },

        // Update / insert return the raw {data,error} so the caller can branch
        // into its local-file fallback on error (without throwing).
        async update(id, payload) {
            return supabase.from(P).update(payload).eq('id', id).select().single();
        },
        async create(payload) {
            return supabase.from(P).insert([payload]).select().single();
        },
        async removeById(id) {
            return supabase.from(P).delete().eq('id', id);
        },

        // Upsert the Google Calendar OAuth token onto the default profile row.
        async saveCalendarToken(tokenJson) {
            return supabase.from(P).upsert(
                [{ id: 'default', google_calendar_token: tokenJson }],
                { onConflict: 'id' },
            );
        },
    };
}

module.exports = { createProfileRepo };
