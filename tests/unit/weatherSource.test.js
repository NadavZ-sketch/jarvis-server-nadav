jest.mock('axios');
const axios = require('axios');
const { _describe } = require('../../services/weatherSource');

beforeEach(() => jest.clearAllMocks());

// Each case loads a fresh module instance so the in-process cache doesn't leak.
function freshModule() {
  let mod;
  jest.isolateModules(() => { mod = require('../../services/weatherSource'); });
  return mod;
}

describe('_describe (WMO mapping)', () => {
  it('maps known codes to Hebrew + emoji', () => {
    expect(_describe(0)[0]).toBe('בהיר');
    expect(_describe(61)[0]).toBe('גשם קל');
    expect(_describe(95)[0]).toBe('סופת רעמים');
  });
  it('falls back gracefully for unknown codes', () => {
    const [desc, emoji] = _describe(1234);
    expect(desc).toBe('');
    expect(typeof emoji).toBe('string');
  });
});

describe('getWeatherSummary', () => {
  function mockGeoAndForecast() {
    axios.get.mockImplementation((url) => {
      if (url.includes('geocoding-api')) {
        return Promise.resolve({
          data: { results: [{ latitude: 32.08, longitude: 34.78, name: 'תל אביב' }] },
        });
      }
      return Promise.resolve({
        data: {
          current: { temperature_2m: 18.4, apparent_temperature: 17, weather_code: 2 },
          daily: {
            temperature_2m_max: [22.3],
            temperature_2m_min: [14.1],
            precipitation_probability_max: [60],
          },
        },
      });
    });
  }

  it('composes a Hebrew summary with temp, range, rain and advice', async () => {
    mockGeoAndForecast();
    const r = await freshModule().getWeatherSummary('תל אביב');
    expect(r).not.toBeNull();
    expect(r.summary).toContain('18°');
    expect(r.summary).toContain('מעונן חלקית');
    expect(r.summary).toContain('22°');
    expect(r.summary).toContain('60% גשם');
    expect(r.summary).toContain('מטרייה'); // rain >= 50 → umbrella advice
  });

  it('returns null when the city cannot be geocoded', async () => {
    axios.get.mockResolvedValue({ data: { results: [] } });
    const r = await freshModule().getWeatherSummary('עיר לא קיימת');
    expect(r).toBeNull();
  });

  it('returns null on network failure', async () => {
    axios.get.mockRejectedValue(new Error('boom'));
    const r = await freshModule().getWeatherSummary('תל אביב');
    expect(r).toBeNull();
  });
});
