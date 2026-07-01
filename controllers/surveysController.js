const { callGemma4 } = require('../agents/models');
const {
  SURVEY_QUESTIONS, selectSurveyQuestions, buildSurveyJson, buildSurveySummary,
  aggregateSurveys, insightsFromAggregation, isNegativeAnswer, generateSmartSurvey,
} = require('../agents/surveyAgent');

// Per-user 48h cooldown after a completed submission; questions answered in
// the last 7 days are excluded from the next survey so it feels fresh.
const SURVEY_COOLDOWN_HOURS = 48;
const SURVEY_EXCLUDE_WINDOW_DAYS = 7;
// Minimum number of completed surveys before we show aggregated conclusions.
// Below this we report "not enough data" instead of inventing insights.
const SURVEY_MIN_FOR_INSIGHTS = 2;

function createSurveysController({ repos, agentMetrics }) {
  return {
    // GET /surveys/export — export survey responses as CSV
    async exportCsv(_req, res) {
      try {
        const rows = await repos.surveys.listAll();
        const header = 'id,question_id,response,created_at';
        const csvRows = rows.map(r =>
          [r.id, r.question_id, JSON.stringify(r.response ?? ''), r.created_at].join(',')
        );
        const csv = [header, ...csvRows].join('\n');
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', 'attachment; filename="surveys.csv"');
        res.send(csv);
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    },

    // POST /surveys/analyze-sentiment — keyword-based sentiment counts (no LLM)
    async analyzeSentiment(req, res) {
      try {
        const { responses } = req.body || {};
        if (!Array.isArray(responses))
          return res.status(400).json({ error: 'responses array required' });

        const POS = ['טוב', 'מעולה', 'אוהב', 'נהדר', 'מצוין', 'great', 'good', 'love', 'excellent', 'awesome'];
        const NEG = ['רע', 'גרוע', 'שונא', 'נורא', 'bad', 'terrible', 'hate', 'awful', 'poor'];

        let positive = 0, negative = 0, neutral = 0;
        for (const r of responses) {
          const text = String(r).toLowerCase();
          const isPos = POS.some(w => text.includes(w));
          const isNeg = NEG.some(w => text.includes(w));
          if (isPos && !isNeg) positive++;
          else if (isNeg && !isPos) negative++;
          else neutral++;
        }
        res.json({ positive, negative, neutral, total: responses.length });
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    },

    // Should user take survey?
    async check(req, res) {
      try {
        const { sessionMinutes, agentCallCount, force, userName } = req.query;
        const minutes = parseInt(sessionMinutes) || 0;
        const calls = parseInt(agentCallCount) || 0;
        const forced = force === 'true' || force === '1';

        // Trigger survey after 25+ minutes OR 8+ agent calls (or forced by user).
        // Higher thresholds keep the survey from interrupting short, active sessions.
        const shouldShowSurvey = forced || minutes >= 25 || calls >= 8;
        if (!shouldShowSurvey) return res.json({ showSurvey: false });

        // Cooldown + recent-question exclusion (requires userName).
        let excludeIds = [];
        if (userName) {
          try {
            const cooldownCutoff = new Date(Date.now() - SURVEY_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString();
            const excludeCutoff  = new Date(Date.now() - SURVEY_EXCLUDE_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();

            // 1) Cooldown: any completed survey since cutoff blocks new prompts.
            if (!forced) {
              const recent = await repos.surveys.recentCompleted(userName, cooldownCutoff);
              if (recent && recent.length > 0) {
                return res.json({ showSurvey: false, cooldown: true });
              }
            }

            // 2) Build exclude list from question_ids of surveys in the last 7 days.
            const recentWeek = await repos.surveys.recentQuestionIds(userName, excludeCutoff);
            for (const row of (recentWeek || [])) {
              for (const qid of (row.question_ids || [])) excludeIds.push(qid);
            }
          } catch (cooldownErr) {
            // If the cooldown columns don't exist yet (migration not applied), proceed without filtering.
            console.warn('⚠️ /survey-check cooldown query failed (will still serve survey):', cooldownErr.message);
          }
        }

        const questions = selectSurveyQuestions({ minutes, calls }, excludeIds);
        if (Object.keys(questions).length === 0) {
          return res.json({ showSurvey: false, exhausted: true });
        }
        const surveyJson = buildSurveyJson(questions);
        res.json({ showSurvey: true, questions: surveyJson });
      } catch (err) {
        console.error('⚠️ /survey-check error:', err.message);
        res.json({ showSurvey: false });
      }
    },

    async submit(req, res) {
      try {
        const { responses, userName } = req.body;
        if (!responses || !userName) {
          return res.status(400).json({ error: 'Missing responses or userName' });
        }

        // Build survey structure from the actually-answered questions.
        const surveyQIds = Object.keys(responses);
        const survey = surveyQIds.map(id => ({
          id,
          question: SURVEY_QUESTIONS[id]?.question || id,
        }));

        // Build a factual summary straight from the answers — no LLM, no invented text.
        const { text: summary, breakdown } = buildSurveySummary(survey, responses, userName);

        // Save survey to DB with completion tracking so future /survey-check
        // calls can enforce the per-user cooldown and exclude answered question_ids.
        const nowIso = new Date().toISOString();
        const insertRow = {
          user_name: userName,
          responses: JSON.stringify(responses),
          summary,
          created_at: nowIso,
          completed_at: nowIso,
          question_ids: surveyQIds,
        };
        const { error } = await repos.surveys.insertGraceful(insertRow);
        if (error) throw error;

        res.json({ success: true, summary, breakdown });
      } catch (err) {
        console.error('⚠️ /survey-submit error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    async history(req, res) {
      try {
        const { userName } = req.query;
        if (!userName) return res.status(400).json({ error: 'userName required' });

        const data = await repos.surveys.historyForUser(userName);

        const surveys = (data || []).map(s => {
          let parsed = s.responses;
          if (typeof parsed === 'string') {
            try { parsed = JSON.parse(parsed); } catch (_) { parsed = {}; }
          }
          return { id: s.id, createdAt: s.created_at, summary: s.summary, responses: parsed };
        });

        res.json({ surveys });
      } catch (err) {
        console.error('⚠️ /survey-history error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    // Real aggregation of stored responses (counts + percentages) — NOT LLM text.
    // Returns enough:false (and no conclusions) until there are enough surveys.
    async insights(req, res) {
      try {
        const { userName } = req.query;
        if (!userName) return res.status(400).json({ error: 'userName required' });

        const data = await repos.surveys.responsesForUser(userName);

        const agg = aggregateSurveys(data || []);
        if (agg.surveyCount < SURVEY_MIN_FOR_INSIGHTS) {
          return res.json({
            enough: false,
            surveyCount: agg.surveyCount,
            minRequired: SURVEY_MIN_FOR_INSIGHTS,
            insights: [],
            aggregation: agg,
          });
        }

        res.json({
          enough: true,
          surveyCount: agg.surveyCount,
          insights: insightsFromAggregation(agg),
          aggregation: agg,
          generatedAt: new Date().toISOString(),
        });
      } catch (err) {
        console.error('⚠️ /survey-insights error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },

    // Reads usage data (agent metrics + past concerns) and lets the LLM craft
    // personalised questions, making each survey feel relevant rather than generic.
    async smartCheck(req, res) {
      const { userName = '' } = req.query;
      try {
        const snap = await agentMetrics.snapshot().catch(() => ({ latency: [] }));
        const topAgents = (snap.latency || [])
          .filter(r => r.count > 0)
          .sort((a, b) => b.count - a.count)
          .slice(0, 5)
          .map(r => ({ agent: r.agent, count: r.count }));

        let pastConcerns = [];
        if (userName) {
          const surveyRows = await repos.surveys.recentResponsesById(userName, 5);
          for (const s of surveyRows || []) {
            let resp = s.responses;
            if (typeof resp === 'string') { try { resp = JSON.parse(resp); } catch (_) { resp = {}; } }
            for (const [qId, answer] of Object.entries(resp || {})) {
              if (isNegativeAnswer(answer) && SURVEY_QUESTIONS[qId]) {
                pastConcerns.push({ area: SURVEY_QUESTIONS[qId].question, answer });
              }
            }
          }
        }

        const questions = await generateSmartSurvey(callGemma4, { topAgents, pastConcerns });
        res.json({ showSurvey: true, questions, smart: true });
      } catch (err) {
        console.error('⚠️ /survey-smart-check error:', err.message);
        res.json({ showSurvey: false });
      }
    },

    // Feedback loop: what concerns came from surveys
    async impact(req, res) {
      const { userName = '' } = req.query;
      try {
        const surveyRows = await repos.surveys.recentResponsesWithDateById(userName, 20);

        const concerns = [];
        for (const s of surveyRows || []) {
          let resp = s.responses;
          if (typeof resp === 'string') { try { resp = JSON.parse(resp); } catch (_) { resp = {}; } }
          for (const [qId, answer] of Object.entries(resp || {})) {
            if (isNegativeAnswer(answer) && SURVEY_QUESTIONS[qId]) {
              concerns.push({ area: SURVEY_QUESTIONS[qId].question, answer, date: s.created_at });
            }
          }
        }
        res.json({ concerns, totalSurveys: (surveyRows || []).length });
      } catch (err) {
        console.error('⚠️ /survey-impact error:', err.message);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
  };
}

module.exports = { createSurveysController };
