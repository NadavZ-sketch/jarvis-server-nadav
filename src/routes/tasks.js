// Routes - ניהול משימות

const express = require('express');
const router = express.Router();
const {
  createTask,
  getAllTasks,
  getOpenTasks,
  completeTask,
  deleteTask,
} = require('../engines/taskManager');

// קבלת כל המשימות
router.get('/', (req, res) => {
  const tasks = getAllTasks();
  res.json({ success: true, tasks });
});

// קבלת משימות פתוחות בלבד
router.get('/open', (req, res) => {
  const tasks = getOpenTasks();
  res.json({ success: true, tasks });
});

// יצירת משימה חדשה
router.post('/', (req, res) => {
  const { title, description, dueDate } = req.body;
  if (!title) {
    return res.status(400).json({ success: false, error: 'כותרת המשימה חובה' });
  }
  const task = createTask(title, description, dueDate);
  res.json({ success: true, task });
});

// סימון משימה כבוצעה
router.put('/:id/complete', (req, res) => {
  const task = completeTask(req.params.id);
  if (!task) {
    return res.status(404).json({ success: false, error: 'משימה לא נמצאה' });
  }
  res.json({ success: true, task });
});

// מחיקת משימה
router.delete('/:id', (req, res) => {
  const tasks = deleteTask(req.params.id);
  res.json({ success: true, tasks });
});

module.exports = router;