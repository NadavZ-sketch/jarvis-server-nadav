// Task Manager - ניהול משימות

const fs = require('fs');
const path = require('path');

const TASKS_FILE = path.join(__dirname, '../../data/tasks.json');

// וודא שתיקיית data קיימת
function ensureDataDir() {
  const dataDir = path.join(__dirname, '../../data');
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
}

// טעינת משימות
function loadTasks() {
  ensureDataDir();
  if (!fs.existsSync(TASKS_FILE)) {
    return [];
  }
  const data = fs.readFileSync(TASKS_FILE, 'utf8');
  return JSON.parse(data);
}

// שמירת משימות
function saveTasks(tasks) {
  ensureDataDir();
  fs.writeFileSync(TASKS_FILE, JSON.stringify(tasks, null, 2), 'utf8');
}

// יצירת משימה חדשה
function createTask(title, description = '', dueDate = null) {
  const tasks = loadTasks();
  const newTask = {
    id: Date.now().toString(),
    title,
    description,
    dueDate,
    completed: false,
    createdAt: new Date().toISOString(),
  };
  tasks.push(newTask);
  saveTasks(tasks);
  return newTask;
}

// קבלת כל המשימות
function getAllTasks() {
  return loadTasks();
}

// קבלת משימות פתוחות בלבד
function getOpenTasks() {
  return loadTasks().filter(t => !t.completed);
}

// סימון משימה כבוצעה
function completeTask(id) {
  const tasks = loadTasks();
  const task = tasks.find(t => t.id === id);
  if (!task) return null;
  task.completed = true;
  task.completedAt = new Date().toISOString();
  saveTasks(tasks);
  return task;
}

// מחיקת משימה
function deleteTask(id) {
  const tasks = loadTasks();
  const filtered = tasks.filter(t => t.id !== id);
  saveTasks(filtered);
  return filtered;
}

module.exports = {
  createTask,
  getAllTasks,
  getOpenTasks,
  completeTask,
  deleteTask,
};