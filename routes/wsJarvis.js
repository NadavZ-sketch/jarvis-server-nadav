// WebSocket handler for live talk mode.
// Mirrors the /stream-jarvis SSE pipeline but speaks JSON frames over WS,
// supports mid-generation barge-in, and optionally returns base64 TTS audio.

function createWsHandler(deps) {
    const {
        classifyIntent,
        contextResolver,
        loadChatHistory,
        fetchLongTermMemories,
        conversationSummary,
        buildSystemPrompt,
        callGemma4Stream,
        runChatAgent,
        runWeatherAgent,
        runNewsAgent,
        runStocksAgent,
        runTranslationAgent,
        saveChatMessage,
        cacheInvalidate,
        autoExtractMemory,
        generateSpeech,
        supabase,
    } = deps;
    // Data-access seam: autoExtractMemory crosses repos.memories.
    const { createRepos } = require('../services/dataAccess');
    const repos = deps.repos || createRepos(supabase);

    return function handleWsConnection(ws /* , req */) {
        const session = {
            chatId: null,
            settings: {},
            useLocal: false,
            generation: null, // { controller: AbortController }
        };

        const send = (obj) => {
            if (ws.readyState !== 1) return;
            try { ws.send(JSON.stringify(obj)); } catch (_) {}
        };

        ws.on('message', async (raw) => {
            let msg;
            try { msg = JSON.parse(raw.toString()); } catch { return; }

            if (msg.type === 'hello') {
                session.chatId = msg.chatId || `ws-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
                session.settings = msg.settings || {};
                session.useLocal = session.settings.useLocalModel === true;
                send({ type: 'ack', chatId: session.chatId });
                return;
            }

            if (msg.type === 'barge_in') {
                if (session.generation?.controller) {
                    session.generation.controller.abort();
                }
                return;
            }

            if (msg.type === 'bye') {
                if (session.generation?.controller) session.generation.controller.abort();
                try { ws.close(); } catch (_) {}
                return;
            }

            if (msg.type !== 'user_text') return;

            const userMessage = (msg.text || '').toString().trim();
            if (!userMessage) return;
            if (userMessage.length > 5000) {
                send({ type: 'error', message: 'ההודעה ארוכה מדי.' });
                return;
            }

            // Cancel any in-flight generation before starting a new one.
            if (session.generation?.controller) session.generation.controller.abort();
            const controller = new AbortController();
            session.generation = { controller };

            const chatId = session.chatId;
            const settings = { ...session.settings, voiceMode: true };
            const useLocal = session.useLocal;

            try {
                // Contextual reference resolution — dispatch on the resolved message,
                // but persist the original below. (No inline nudge in voice mode.)
                let dispatchMessage = userMessage;
                if (contextResolver && contextResolver.shouldResolve(userMessage)) {
                    const [h, s] = await Promise.all([
                        loadChatHistory(chatId),
                        conversationSummary.getSummary(chatId, supabase),
                    ]);
                    const { resolved, didResolve } = await contextResolver.resolveReferences(userMessage, h, s);
                    if (didResolve) dispatchMessage = resolved;
                }

                const agentName = await classifyIntent(dispatchMessage);
                send({ type: 'thinking', agent: agentName });

                let fullAnswer = '';

                if (['chat', 'draft'].includes(agentName)) {
                    const [chatHistory, longTermMemories, chatSummary] = await Promise.all([
                        loadChatHistory(chatId),
                        fetchLongTermMemories(dispatchMessage),
                        conversationSummary.getSummary(chatId, supabase),
                    ]);
                    settings.chatSummary = chatSummary;
                    const systemPrompt = buildSystemPrompt(chatHistory, longTermMemories, settings, null, dispatchMessage);
                    const msgs = [
                        { role: 'system', content: systemPrompt },
                        ...chatHistory.map(m => ({ role: m.role === 'jarvis' ? 'assistant' : 'user', content: m.text })),
                        { role: 'user', content: dispatchMessage },
                    ];

                    await callGemma4Stream(msgs, useLocal, (chunk) => {
                        fullAnswer += chunk;
                        send({ type: 'assistant_chunk', text: chunk });
                    }, controller.signal, 200);
                } else {
                    let result;
                    if (agentName === 'weather')         result = await runWeatherAgent(dispatchMessage);
                    else if (agentName === 'news')       result = await runNewsAgent(dispatchMessage);
                    else if (agentName === 'stocks')     result = await runStocksAgent(dispatchMessage);
                    else if (agentName === 'translate')  result = await runTranslationAgent(dispatchMessage, supabase, useLocal);
                    else {
                        const [chatHistory, longTermMemories] = await Promise.all([
                            loadChatHistory(chatId), fetchLongTermMemories(),
                        ]);
                        result = await runChatAgent(dispatchMessage, null, chatHistory, longTermMemories, settings);
                    }
                    fullAnswer = result.answer || '';
                    send({ type: 'assistant_chunk', text: fullAnswer });
                }

                // Generate TTS in parallel-ish: client renders text immediately,
                // audio arrives moments later with assistant_done.
                const ttsEnabled = settings.ttsEnabled !== false;
                const audio = ttsEnabled ? await generateSpeech(fullAnswer) : null;

                if (controller.signal.aborted) {
                    send({ type: 'aborted' });
                } else {
                    send({ type: 'assistant_done', text: fullAnswer, audio, chatId });
                }

                await Promise.all([
                    saveChatMessage('user', userMessage, chatId),
                    saveChatMessage('jarvis', fullAnswer, chatId),
                ]);
                cacheInvalidate(`chatHistory:${chatId}`);

                setImmediate(() => {
                    autoExtractMemory(userMessage, fullAnswer, repos, settings).catch(() => {});
                    loadChatHistory(chatId).then(fresh => {
                        conversationSummary.updateSummaryIfNeeded(chatId, fresh, supabase, settings).catch(() => {});
                    }).catch(() => {});
                });
            } catch (err) {
                if (controller.signal.aborted) {
                    send({ type: 'aborted' });
                } else {
                    console.error('WS jarvis error:', err.message);
                    send({ type: 'error', message: 'שגיאת מערכת.' });
                }
            } finally {
                if (session.generation?.controller === controller) session.generation = null;
            }
        });

        ws.on('close', () => {
            if (session.generation?.controller) session.generation.controller.abort();
        });

        ws.on('error', () => {
            if (session.generation?.controller) session.generation.controller.abort();
        });
    };
}

module.exports = { createWsHandler };
