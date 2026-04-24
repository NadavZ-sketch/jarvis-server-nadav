// Escapes % _ \ wildcards from user input before ilike pattern matching
function sanitizeLike(str) {
    return String(str).replace(/[\\%_]/g, '\\$&');
}

module.exports = { sanitizeLike };
