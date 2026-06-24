'use strict';

// Playlist repository — data-access seam for the `playlist` table (musicAgent).
// Reads return rows (or []); deleteByTitle returns deleted rows so the caller
// can confirm the song name; add returns the raw Supabase result.

const { sanitizeLike } = require('../../agents/utils');

const P = 'playlist';

function createPlaylistRepo(supabase) {
    return {
        async list(limit = 20) {
            const { data, error } = await supabase.from(P)
                .select('title, artist')
                .order('created_at', { ascending: false })
                .limit(limit);
            if (error) throw error;
            return data || [];
        },

        async add(title, artist = '') {
            return supabase.from(P).insert([{ title, artist }]);
        },

        async deleteByTitle(term) {
            const { data, error } = await supabase.from(P)
                .delete()
                .ilike('title', `%${sanitizeLike(term)}%`)
                .select();
            if (error) throw error;
            return data || [];
        },
    };
}

module.exports = { createPlaylistRepo };
