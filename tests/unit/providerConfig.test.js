'use strict';

const { resolveChain, clampTemp, LocalModelError, PROVIDERS } = require('../../agents/providerConfig');

describe('resolveChain', () => {
    test('useLocal → strict local (ollama only)', () => {
        expect(resolveChain({ useLocal: true })).toEqual(['ollama']);
        // cloudProvider is ignored when local is on
        expect(resolveChain({ useLocal: true, cloudProvider: 'deepseek' })).toEqual(['ollama']);
    });

    test('default cloud order when no provider chosen', () => {
        expect(resolveChain({})).toEqual(['groq', 'deepseek', 'openrouter', 'gemini']);
    });

    test('chosen cloud provider moves to the front, rest kept as fallback', () => {
        expect(resolveChain({ cloudProvider: 'deepseek' }))
            .toEqual(['deepseek', 'groq', 'openrouter', 'gemini']);
        expect(resolveChain({ cloudProvider: 'gemini' }))
            .toEqual(['gemini', 'groq', 'deepseek', 'openrouter']);
    });

    test('unknown cloud provider falls back to default order', () => {
        expect(resolveChain({ cloudProvider: 'bogus' }))
            .toEqual(['groq', 'deepseek', 'openrouter', 'gemini']);
    });
});

describe('clampTemp', () => {
    test('valid temperature passes through', () => {
        expect(clampTemp(0)).toBe(0);
        expect(clampTemp(0.9)).toBe(0.9);
        expect(clampTemp(2)).toBe(2);
    });
    test('invalid / out-of-range / missing → 0.5 default', () => {
        expect(clampTemp(undefined)).toBe(0.5);
        expect(clampTemp(-1)).toBe(0.5);
        expect(clampTemp(5)).toBe(0.5);
        expect(clampTemp('hot')).toBe(0.5);
    });
});

describe('PROVIDERS enabled gates', () => {
    test('ollama enabled only when a local url is configured', () => {
        expect(PROVIDERS.ollama.enabled({ localServerUrl: 'http://x:11434' })).toBe(true);
        const prev = process.env.OLLAMA_URL;
        delete process.env.OLLAMA_URL;
        expect(PROVIDERS.ollama.enabled({})).toBe(false);
        if (prev !== undefined) process.env.OLLAMA_URL = prev;
    });
    test('groq / deepseek / gemini are always attempted', () => {
        expect(PROVIDERS.groq.enabled({})).toBe(true);
        expect(PROVIDERS.deepseek.enabled({})).toBe(true);
        expect(PROVIDERS.gemini.enabled({})).toBe(true);
    });
    test('ollama honors settings url/model over env', () => {
        expect(PROVIDERS.ollama.url({ localServerUrl: 'http://host:11434' })).toBe('http://host:11434');
        expect(PROVIDERS.ollama.model({ localModelName: 'qwen2.5' })).toBe('qwen2.5');
    });
});

describe('LocalModelError', () => {
    test('carries url and model', () => {
        const e = new LocalModelError('down', { url: 'http://x', model: 'm' });
        expect(e.name).toBe('LocalModelError');
        expect(e.url).toBe('http://x');
        expect(e.model).toBe('m');
        expect(e instanceof Error).toBe(true);
    });
});
