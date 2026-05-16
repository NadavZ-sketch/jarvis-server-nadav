const fs = require('fs');
const path = require('path');

const POLICY_PATH = path.join(__dirname, '..', 'config', 'policyRules.json');

let cached = null;

function loadPolicyRules() {
  if (cached) return cached;
  try {
    const raw = fs.readFileSync(POLICY_PATH, 'utf8');
    cached = JSON.parse(raw);
  } catch (_) {
    cached = { blocklist: [], allowlist: {} };
  }
  return cached;
}

function isAllowedByRolePlan({ actionType, role = 'member', plan = 'free' }) {
  const rules = loadPolicyRules();
  const allowed = rules?.allowlist?.[plan]?.[role] || [];
  return allowed.includes('*') || allowed.includes(actionType);
}

function isBlockedAction(actionType) {
  const rules = loadPolicyRules();
  return (rules?.blocklist || []).includes(actionType);
}

module.exports = { loadPolicyRules, isAllowedByRolePlan, isBlockedAction };
