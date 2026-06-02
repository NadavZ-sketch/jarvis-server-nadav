'use strict';

/**
 * Lightweight PDF text extraction for the "ask about this document" flow.
 *
 * Wraps pdf-parse (v2) so the rest of the server doesn't depend on its API
 * shape. Returns plain text, capped to a sane length so a huge PDF can't blow
 * the LLM context budget. Never throws — callers get { ok, text, ... }.
 */

const { PDFParse } = require('pdf-parse');

// Decoded-size guard (10 MB) — mirrors the image cap in models.js.
const MAX_PDF_BYTES = 10 * 1024 * 1024;
// Cap extracted text so a long PDF stays within the LLM context budget.
const MAX_TEXT_CHARS = 12000;

/**
 * Extract text from a base64-encoded PDF.
 * @param {string} pdfBase64 - raw base64 (no data: prefix)
 * @returns {Promise<{ok:boolean, text?:string, pages?:number, truncated?:boolean, reason?:string}>}
 */
async function extractPdfText(pdfBase64) {
    if (!pdfBase64 || typeof pdfBase64 !== 'string') {
        return { ok: false, reason: 'no_pdf' };
    }
    let buffer;
    try {
        buffer = Buffer.from(pdfBase64, 'base64');
    } catch {
        return { ok: false, reason: 'invalid_base64' };
    }
    if (buffer.length === 0) return { ok: false, reason: 'empty' };
    if (buffer.length > MAX_PDF_BYTES) return { ok: false, reason: 'too_large' };

    try {
        const parser = new PDFParse({ data: buffer });
        const result = await parser.getText();
        let text = (result?.text || '').trim();
        if (!text) return { ok: false, reason: 'no_text' };

        const truncated = text.length > MAX_TEXT_CHARS;
        if (truncated) text = text.slice(0, MAX_TEXT_CHARS);

        return {
            ok: true,
            text,
            pages: result?.total || result?.pages || null,
            truncated,
        };
    } catch (err) {
        console.error('⚠️ extractPdfText failed:', err.message);
        return { ok: false, reason: err.message };
    }
}

module.exports = { extractPdfText, MAX_PDF_BYTES, MAX_TEXT_CHARS };
