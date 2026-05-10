function createChatController({ supabase, askJarvisHandler, streamJarvisHandler }) {
  return {
    async askJarvis(req, res) {
      if (typeof askJarvisHandler !== 'function') {
        return res.status(500).json({ answer: 'Chat handler not configured.' });
      }
      return askJarvisHandler(req, res);
    },
    async getChatHistory(req, res) {
      try {
        const chatId = req.query.chatId || req.query.chat_id || 'default-session';
        const limit = Math.min(parseInt(req.query.limit, 10) || 60, 200);
        const { data, error } = await supabase
          .from('chat_history')
          .select('role, text, created_at')
          .eq('chat_id', chatId)
          .order('created_at', { ascending: false })
          .limit(limit);
        if (error) throw error;
        res.json({ messages: (data || []).reverse(), chatId });
      } catch (err) {
        console.error('⚠️ /chat-history error:', err.message);
        res.status(500).json({ messages: [], chatId: 'default-session' });
      }
    },
    async streamJarvis(req, res) {
      if (typeof streamJarvisHandler !== 'function') {
        return res.status(500).json({ error: 'Stream handler not configured.' });
      }
      return streamJarvisHandler(req, res);
    },
  };
}

module.exports = { createChatController };
