// UX / Hebrew-quality scan — grades samples produced by apiProbe.

const { callGemma4 } = require('../models');

const RUBRIC_PROMPT = `דרג את התשובה של עוזר אישי בעברית במנעד 0-10 לפי ארבעה ממדים:
- relevance: עד כמה התשובה רלוונטית לשאלה
- fluency: עד כמה העברית רהוטה ותקינה
- grounding: עד כמה התשובה מבוססת על המידע שנתבקש (לא הזיה)
- helpfulness: עד כמה התשובה מועילה

החזר JSON תקין בלבד:
{"relevance":N,"fluency":N,"grounding":N,"helpfulness":N,"comments":"<קצר>"}

`;

function severityForScore(min, avg) {
    if (min < 4) return 'high';
    if (min <= 5 || avg < 6) return 'medium';
    if (avg < 8) return 'low';
    return null;
}

async function gradeSample(query, answer) {
    const prompt = `${RUBRIC_PROMPT}שאלה: ${query}\nתשובה: ${answer}`;
    let raw = '';
    try { raw = await callGemma4(prompt, false, 200); }
    catch { return null; }
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try { return JSON.parse(m[0]); } catch { return null; }
}

async function runUxScan({ samples = [], learnedContext = {} } = {}) {
    const findings = [];
    if (!samples.length) return { findings };

    for (const s of samples) {
        if (!s.answer) continue;
        const graded = await gradeSample(s.query, s.answer);
        if (!graded) continue;

        const dims = ['relevance', 'fluency', 'grounding', 'helpfulness']
            .map(k => Number(graded[k]))
            .filter(Number.isFinite);
        if (!dims.length) continue;

        const min = Math.min(...dims);
        const avg = dims.reduce((a, b) => a + b, 0) / dims.length;
        const sev = severityForScore(min, avg);
        if (!sev) continue;

        findings.push({
            severity: sev,
            category: 'quality',
            target: 'POST /ask-jarvis',
            finding: `איכות תשובה נמוכה ל-"${s.query}" (avg=${avg.toFixed(1)}, min=${min}). ${graded.comments || ''}`.trim(),
            recommendation: 'חזק את הפרומפט של הסוכן הרלוונטי או הוסף grounding לזיכרונות.',
            score: Math.round(avg * 10),
        });
    }

    return { findings };
}

module.exports = { runUxScan };
