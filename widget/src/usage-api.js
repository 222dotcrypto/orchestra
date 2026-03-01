const { execFile } = require('child_process');
const https = require('https');

const CACHE_TTL_MS = 120_000;
let cached = null;
let cachedAt = 0;

function getAccessToken() {
  return new Promise((resolve, reject) => {
    execFile('security', ['find-generic-password', '-s', 'Claude Code-credentials', '-w'], {
      timeout: 5000
    }, (err, stdout) => {
      if (err) return reject(new Error('Keychain: ' + err.message));
      try {
        const creds = JSON.parse(stdout.trim());
        const token = creds?.claudeAiOauth?.accessToken;
        if (!token) return reject(new Error('No accessToken in credentials'));
        resolve(token);
      } catch (e) {
        reject(new Error('Parse credentials: ' + e.message));
      }
    });
  });
}

function fetchFromApi(token) {
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.anthropic.com',
      path: '/api/oauth/usage',
      method: 'GET',
      timeout: 5000,
      headers: {
        'Authorization': `Bearer ${token}`,
        'anthropic-beta': 'oauth-2025-04-20',
        'Accept': 'application/json'
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode !== 200) {
          return reject(new Error(`API ${res.statusCode}: ${body.slice(0, 100)}`));
        }
        try { resolve(JSON.parse(body)); }
        catch (e) { reject(new Error('Parse: ' + e.message)); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.end();
  });
}

async function fetchUsageLimits() {
  const now = Date.now();
  if (cached && (now - cachedAt) < CACHE_TTL_MS) return cached;

  try {
    const token = await getAccessToken();
    const data = await fetchFromApi(token);
    const result = {
      h5Util: data.five_hour?.utilization ?? 0,
      h5Reset: data.five_hour?.resets_at ?? null,
      wUtil: data.seven_day?.utilization ?? 0,
      wReset: data.seven_day?.resets_at ?? null
    };
    cached = result;
    cachedAt = now;
    return result;
  } catch (err) {
    console.error('Usage API error:', err.message);
    return cached;
  }
}

module.exports = { fetchUsageLimits };
