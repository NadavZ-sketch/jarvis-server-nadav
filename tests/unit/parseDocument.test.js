'use strict';

jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({ createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn() }) }));
jest.mock('openai', () => ({ OpenAI: jest.fn().mockImplementation(() => ({ audio: { transcriptions: { create: jest.fn() } } })), toFile: jest.fn() }));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: '' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({ initSync: jest.fn(), fullSyncFromDb: jest.fn(), appendChatMessage: jest.fn(), syncAll: jest.fn() }));
jest.mock('../../services/weatherSource', () => ({ getWeatherSummary: jest.fn().mockResolvedValue(null) }));
jest.mock('../../services/newsSource', () => ({ getNewsSummary: jest.fn().mockResolvedValue(null), getTopicHeadlines: jest.fn().mockResolvedValue(null) }));
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn(), callGemma4Stream: jest.fn() }));

// Mock pdf-parse and mammoth so tests don't need real files.
jest.mock('pdf-parse', () => jest.fn());
jest.mock('mammoth', () => ({ extractRawText: jest.fn() }));

const request = require('supertest');
const pdfParse = require('pdf-parse');
const mammoth = require('mammoth');
const { app } = require('../../server');

describe('POST /parse-document', () => {
    beforeEach(() => jest.clearAllMocks());

    it('returns 400 when no fileBase64 provided', async () => {
        const res = await request(app).post('/parse-document').send({ fileType: 'pdf' });
        expect(res.status).toBe(400);
        expect(res.body).toHaveProperty('error');
    });

    it('parses PDF and returns text', async () => {
        pdfParse.mockResolvedValue({ text: 'שלום עולם', numpages: 1 });
        const fakeBase64 = Buffer.from('fake-pdf').toString('base64');
        const res = await request(app).post('/parse-document').send({
            fileBase64: fakeBase64,
            fileType: 'pdf',
        });
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('text', 'שלום עולם');
        expect(res.body).toHaveProperty('pages', 1);
    });

    it('parses docx and returns text', async () => {
        mammoth.extractRawText.mockResolvedValue({ value: 'תוכן מסמך' });
        const fakeBase64 = Buffer.from('fake-docx').toString('base64');
        const res = await request(app).post('/parse-document').send({
            fileBase64: fakeBase64,
            fileType: 'docx',
        });
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('text', 'תוכן מסמך');
    });

    it('returns error for unsupported file type', async () => {
        const res = await request(app).post('/parse-document').send({
            fileBase64: 'aGVsbG8=',
            fileType: 'xlsx',
        });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/סוג קובץ/);
    });

    it('truncates text longer than 8000 chars', async () => {
        const longText = 'א'.repeat(10000);
        pdfParse.mockResolvedValue({ text: longText, numpages: 50 });
        const res = await request(app).post('/parse-document').send({
            fileBase64: Buffer.from('x').toString('base64'),
            fileType: 'pdf',
        });
        expect(res.status).toBe(200);
        expect(res.body.text.length).toBeLessThanOrEqual(8000);
    });
});
