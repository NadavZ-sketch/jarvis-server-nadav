'use strict';

// pdf-parse v2 spins up a pdfjs worker via dynamic import, which jest's VM
// cannot load without --experimental-vm-modules. Real extraction is verified
// in plain node; here we mock PDFParse to validate the wrapper's own logic
// (guards, truncation, error handling, return shape) deterministically.
let mockGetText;
jest.mock('pdf-parse', () => ({
    PDFParse: jest.fn().mockImplementation(() => ({
        getText: (...args) => mockGetText(...args),
    })),
}));

const { extractPdfText, MAX_PDF_BYTES, MAX_TEXT_CHARS } = require('../../services/documentParser');

const okB64 = Buffer.from('%PDF-1.4 fake').toString('base64');

beforeEach(() => {
    mockGetText = jest.fn().mockResolvedValue({ text: 'Hello PDF', total: 1 });
});

describe('extractPdfText', () => {
    it('extracts and returns text + page count', async () => {
        const r = await extractPdfText(okB64);
        expect(r.ok).toBe(true);
        expect(r.text).toBe('Hello PDF');
        expect(r.pages).toBe(1);
        expect(r.truncated).toBe(false);
    });

    it('truncates text over the char cap and flags it', async () => {
        mockGetText.mockResolvedValue({ text: 'x'.repeat(MAX_TEXT_CHARS + 500), total: 99 });
        const r = await extractPdfText(okB64);
        expect(r.ok).toBe(true);
        expect(r.truncated).toBe(true);
        expect(r.text.length).toBe(MAX_TEXT_CHARS);
    });

    it('returns no_text when the PDF has no extractable text', async () => {
        mockGetText.mockResolvedValue({ text: '   ' });
        const r = await extractPdfText(okB64);
        expect(r.ok).toBe(false);
        expect(r.reason).toBe('no_text');
    });

    it('never throws when the parser fails', async () => {
        mockGetText.mockRejectedValue(new Error('corrupt pdf'));
        const r = await extractPdfText(okB64);
        expect(r.ok).toBe(false);
        expect(r.reason).toBe('corrupt pdf');
    });

    it('rejects missing input before touching the parser', async () => {
        expect((await extractPdfText()).reason).toBe('no_pdf');
        expect((await extractPdfText('')).reason).toBe('no_pdf');
        expect(mockGetText).not.toHaveBeenCalled();
    });

    it('rejects a buffer over the size cap before touching the parser', async () => {
        const big = Buffer.alloc(MAX_PDF_BYTES + 1024, 0x20).toString('base64');
        const r = await extractPdfText(big);
        expect(r.ok).toBe(false);
        expect(r.reason).toBe('too_large');
        expect(mockGetText).not.toHaveBeenCalled();
    });
});
