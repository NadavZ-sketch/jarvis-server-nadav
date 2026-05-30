// Code Error Agent — chat-triggered wrapper around codeErrorScanner.
// Triggered via "סרוק שגיאות קוד" etc. Returns a human-readable report
// with a Claude Code / Codex ready prompt block appended.

const { runCodeErrorScanner } = require('./e2e/codeErrorScanner');
const { runManusTask, isManusConfigured } = require('./manusAgent');

const SEV_EMOJI = { critical: '🔴', high: '🟠', medium: '🟡', low: '🟢' };

function formatFindingLine(f) {
    return `${SEV_EMOJI[f.severity] || '⚪'} [${(f.severity || '').toUpperCase()}] ${f.target}\n   ${f.finding}\n   ✅ ${f.recommendation || ''}`;
}

async function runCodeErrorAgent(userMessage = '', _useLocal, sendEmailFn) {
    try {
        const { findings, claudePrompt, summary, score } = await runCodeErrorScanner({});

        // Optionally offload the LLM analysis step to Manus
        if (process.env.MANUS_OFFLOAD_CODE_ERROR === 'true' && isManusConfigured() && findings.length > 0) {
            console.log('🔍 CodeErrorAgent: offloading analysis to Manus');
            const { answer: manusAnswer } = await runManusTask(claudePrompt).catch(() => ({ answer: null }));
            if (manusAnswer) return { answer: manusAnswer };
            // fall through to normal formatting on Manus failure
        }

        const counts = { critical: 0, high: 0, medium: 0, low: 0 };
        findings.forEach(f => { if (f.severity in counts) counts[f.severity]++; });

        const lines = findings.length > 0
            ? findings.map(formatFindingLine).join('\n\n')
            : '✅ לא נמצאו שגיאות קוד.';

        const header = [
            `🔍 דוח שגיאות קוד (ציון: ${score}/100)`,
            `🔴 קריטי: ${counts.critical}  🟠 גבוה: ${counts.high}  🟡 בינוני: ${counts.medium}  🟢 נמוך: ${counts.low}`,
            '',
            lines,
            '',
            `📋 סיכום: ${summary}`,
        ].join('\n');

        const claudeBlock = findings.length ? [
            '',
            '═══════════════════════════════════════════',
            '📋 לתיקון בקלוד קוד / Codex — העתק את הבלוק הבא:',
            '═══════════════════════════════════════════',
            '',
            claudePrompt,
        ].join('\n') : '';

        const answer = header + claudeBlock;

        const sendReport = /שלח|מייל|email|דוח ב|report/i.test(userMessage);
        if (sendReport && sendEmailFn && findings.length) {
            const emailBody = [
                `דוח שגיאות קוד — Jarvis (ציון: ${score}/100)`,
                `סיכום: ${summary}`,
                '',
                findings.map(f =>
                    `[${(f.severity || '').toUpperCase()}] ${f.target}\nבעיה: ${f.finding}\nתיקון: ${f.recommendation}`
                ).join('\n\n---\n\n'),
            ].join('\n');

            try {
                await sendEmailFn(process.env.GMAIL_USER, emailBody);
                return { answer: answer + '\n\n📧 הדוח נשלח למייל.' };
            } catch (e) {
                console.warn('codeErrorAgent: email failed:', e.message);
            }
        }

        return { answer };
    } catch (err) {
        console.error('codeErrorAgent Error:', err.message);
        return { answer: 'לא הצלחתי לסרוק את הקוד. נסה שוב.' };
    }
}

module.exports = { runCodeErrorAgent };
