require('dotenv').config();
fetch('http://localhost:3000/ask-jarvis', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'X-API-Key': process.env.APP_SECRET
    },
    body: JSON.stringify({ command: 'תראה לי את רשימת המשימות שלי' })
})
.then(res => res.json())
.then(data => console.log('Jarvis replied:', data.answer));