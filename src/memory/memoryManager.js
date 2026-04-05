// Memory Manager - זיכרון העוזרת

const fs = require('fs');
const path = require('path');

const MEMORY_FILE = path.join(__dirname, '../../data/memory.json');

// וודא שתיקיית data קיימת
function ensureDataDir() {
  const dataDir = path.join(__dirname, '../../data');
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
}

// טעינת זיכרון
function loadMemory() {
  ensureDataDir();
  if (!fs.existsSync(MEMORY_FILE)) {
    return {
      preferences: {},
      history: [],
      facts: [],
    };
  }
  const data = fs.readFileSync(MEMORY_FILE, 'utf8');
  return JSON.parse(data);
}

// שמירת זיכרון
function saveMemory(memory) {
  ensureDataDir();
  fs.writeFileSync(MEMORY_FILE, JSON.stringify(memory, null, 2), 'utf8');
}

// הוספת הודעה להיסטוריה
function addToHistory(role, content) {
  const memory = loadMemory();
  memory.history.push({
    role,
    content,
    timestamp: new Date().toISOString(),
  });

  // שמור רק 50 הודעות אחרונות
  if (memory.history.length > 50) {
    memory.history = memory.history.slice(-50);
  }

  saveMemory(memory);
}

// שמירת עובדה על המשתמש
function saveFact(fact) {
  const memory = loadMemory();
  memory.facts.push({
    fact,
    timestamp: new Date().toISOString(),
  });
  saveMemory(memory);
}

// שמירת העדפה
function savePreference(key, value) {
  const memory = loadMemory();
  memory.preferences[key] = value;
  saveMemory(memory);
}

// קבלת היסטוריה אחרונה
function getRecentHistory(limit = 10) {
  const memory = loadMemory();
  return memory.history.slice(-limit);
}

// קבלת כל הזיכרון
function getFullMemory() {
  return loadMemory();
}

module.exports = {
  saveMemory,
  addToHistory,
  saveFact,
  savePreference,
  getRecentHistory,
  getFullMemory,
};