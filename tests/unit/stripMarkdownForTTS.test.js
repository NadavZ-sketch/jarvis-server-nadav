'use strict';

// We need the function from server.js, but server.js has side-effects (cron,
// Supabase init). The clean way is to test it inline here — it's a pure
// one-file function that can be extracted and verified without the full server.

// Replicate the implementation so we can test it in isolation without importing
// the entire server.js. If the implementation changes, update this mirror too.
function stripMarkdownForTTS(text) {
    return text
        .replace(/\*\*([^*]+)\*\*/g, '$1')
        .replace(/\*([^*]+)\*/g, '$1')
        .replace(/`([^`]+)`/g, '$1')
        .replace(/#{1,6}\s+/g, '')
        .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
        .replace(/^[-•*]\s+/gm, '')
        // Strip emoji
        // eslint-disable-next-line no-misleading-character-class
        .replace(/[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}]/gu, '')
        .replace(/\n{2,}/g, '. ')
        .replace(/\n/g, ' ')
        .replace(/\s{2,}/g, ' ')
        .trim();
}

describe('stripMarkdownForTTS', () => {
    it('strips bold markdown', () => {
        expect(stripMarkdownForTTS('**חם** בחוץ')).toBe('חם בחוץ');
    });

    it('strips italic markdown', () => {
        expect(stripMarkdownForTTS('*הערה* חשובה')).toBe('הערה חשובה');
    });

    it('strips inline code', () => {
        expect(stripMarkdownForTTS('הפעל `npm install`')).toBe('הפעל npm install');
    });

    it('strips headings', () => {
        expect(stripMarkdownForTTS('## כותרת ראשית')).toBe('כותרת ראשית');
    });

    it('strips markdown links but keeps link text', () => {
        expect(stripMarkdownForTTS('[לחץ כאן](https://example.com)')).toBe('לחץ כאן');
    });

    it('strips bullet list markers', () => {
        const input = '- פריט א\n- פריט ב';
        expect(stripMarkdownForTTS(input)).not.toContain('- ');
    });

    it('removes emoji and collapses the resulting extra spaces', () => {
        expect(stripMarkdownForTTS('שלום 🙏 מה שלומך 😊')).toBe('שלום מה שלומך');
    });

    it('removes common weather/status emoji', () => {
        expect(stripMarkdownForTTS('☀️ מזג אוויר יפה')).not.toMatch(/[☀⚡⭐]/u);
    });

    it('collapses multiple spaces left by emoji removal', () => {
        expect(stripMarkdownForTTS('טוב 🎉 מאוד 🎊 יפה')).toBe('טוב מאוד יפה');
    });

    it('converts double newlines to period+space', () => {
        expect(stripMarkdownForTTS('שורה א\n\nשורה ב')).toBe('שורה א. שורה ב');
    });

    it('returns plain Hebrew text unchanged', () => {
        const plain = 'מה מזג האוויר מחר בתל אביב?';
        expect(stripMarkdownForTTS(plain)).toBe(plain);
    });
});
