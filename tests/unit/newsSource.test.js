jest.mock('axios');
const axios = require('axios');
const { getNewsSummary, parseHeadlines } = require('../../services/newsSource');

beforeEach(() => jest.clearAllMocks());

const SAMPLE_RSS = `<?xml version="1.0"?>
<rss><channel>
  <title>Google News</title>
  <item><title>ראש הממשלה נאם בכנסת - ynet</title><link>x</link></item>
  <item><title><![CDATA[מזג האוויר: גשם צפוי מחר - וואלה]]></title></item>
  <item><title>נבחרת ישראל ניצחה 2:0 &amp; עלתה לגמר - ספורט5</title></item>
  <item><title>עוד כותרת חמישית - מקור</title></item>
  <item><title>כותרת שישית שלא אמורה להופיע - מקור</title></item>
</channel></rss>`;

describe('parseHeadlines', () => {
  it('extracts titles, strips source and decodes entities', () => {
    const out = parseHeadlines(SAMPLE_RSS, 4);
    expect(out).toHaveLength(4);
    expect(out[0]).toBe('ראש הממשלה נאם בכנסת');
    expect(out[1]).toBe('מזג האוויר: גשם צפוי מחר'); // CDATA unwrapped
    expect(out[2]).toBe('נבחרת ישראל ניצחה 2:0 & עלתה לגמר'); // &amp; decoded
  });

  it('respects the limit', () => {
    expect(parseHeadlines(SAMPLE_RSS, 2)).toHaveLength(2);
  });

  it('returns [] for empty/invalid input', () => {
    expect(parseHeadlines('', 4)).toEqual([]);
    expect(parseHeadlines(null, 4)).toEqual([]);
    expect(parseHeadlines('<rss></rss>', 4)).toEqual([]);
  });
});

// Each case loads a fresh module instance so the in-process cache doesn't leak.
function freshModule() {
  let mod;
  jest.isolateModules(() => { mod = require('../../services/newsSource'); });
  return mod;
}

describe('getNewsSummary', () => {
  it('returns a bulleted summary from the feed', async () => {
    axios.get.mockResolvedValue({ data: SAMPLE_RSS });
    const r = await freshModule().getNewsSummary();
    expect(r).not.toBeNull();
    expect(r.headlines.length).toBeGreaterThan(0);
    expect(r.summary).toContain('•');
    expect(r.summary).toContain('ראש הממשלה');
  });

  it('returns null on network failure', async () => {
    axios.get.mockRejectedValue(new Error('boom'));
    const r = await freshModule().getNewsSummary();
    expect(r).toBeNull();
  });
});
