const { _internals } = require('../../services/obsidianSync');
const { hashContent, extractCategory, filePathForRecord, sanitizeFilename, ENTITY_DIRS } = _internals;

describe('obsidianSync — internals', () => {

    describe('hashContent', () => {
        test('produces consistent 12-char hex', () => {
            const h = hashContent('hello world');
            expect(h).toHaveLength(12);
            expect(h).toBe(hashContent('hello world'));
        });

        test('different content → different hash', () => {
            expect(hashContent('abc')).not.toBe(hashContent('xyz'));
        });
    });

    describe('sanitizeFilename', () => {
        test('removes illegal characters', () => {
            expect(sanitizeFilename('hello/world:test')).toBe('hello_world_test');
        });

        test('trims to 80 chars', () => {
            const long = 'a'.repeat(100);
            expect(sanitizeFilename(long)).toHaveLength(80);
        });

        test('falls back to "untitled" for empty string', () => {
            expect(sanitizeFilename('')).toBe('untitled');
            expect(sanitizeFilename(null)).toBe('untitled');
        });
    });

    describe('extractCategory', () => {
        test('extracts bracketed category', () => {
            expect(extractCategory('[Personal] my birthday is June 1')).toBe('Personal');
            expect(extractCategory('[Work] project deadline Friday')).toBe('Work');
        });

        test('returns null when no bracket', () => {
            expect(extractCategory('no category here')).toBeNull();
        });

        test('handles empty/null', () => {
            expect(extractCategory(null)).toBeNull();
            expect(extractCategory('')).toBeNull();
        });
    });

    describe('filePathForRecord', () => {
        test('notes → Notes/<title>.md', () => {
            const rec = { id: 'abc-123', title: 'Meeting Notes', content: 'stuff' };
            expect(filePathForRecord('notes', rec)).toBe('Notes/Meeting Notes.md');
        });

        test('notes with no title uses content prefix', () => {
            const rec = { id: 'abc-123', title: '', content: 'Hello this is a note' };
            const p = filePathForRecord('notes', rec);
            expect(p).toMatch(/^Notes\/.+\.md$/);
        });

        test('memories → Memories/<category>.md', () => {
            const rec = { id: 'abc', content: '[Work] deadline is Friday' };
            expect(filePathForRecord('memories', rec)).toBe('Memories/Work.md');
        });

        test('memories with no category → Memories/General.md', () => {
            const rec = { id: 'abc', content: 'some memory without bracket' };
            expect(filePathForRecord('memories', rec)).toBe('Memories/General.md');
        });

        test('tasks → Tasks/tasks.md', () => {
            const rec = { id: 'abc', content: 'Buy milk' };
            expect(filePathForRecord('tasks', rec)).toBe('Tasks/tasks.md');
        });

        test('reminders → Reminders/reminders.md', () => {
            const rec = { id: 'abc', content: 'Call mom' };
            expect(filePathForRecord('reminders', rec)).toBe('Reminders/reminders.md');
        });
    });

    describe('ENTITY_DIRS mapping', () => {
        test('all required entities have a directory', () => {
            const required = ['notes', 'memories', 'tasks', 'reminders', 'chat_history', 'projects'];
            for (const e of required) {
                expect(ENTITY_DIRS[e]).toBeTruthy();
            }
        });
    });
});
