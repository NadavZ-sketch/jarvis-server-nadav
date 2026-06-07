'use strict';

// Maps MCP tool names (namespaced "server__tool") to Jarvis policy action types
// and sensitivity flags consumed by mcpClientManager.guardedCallTool.
//
// Fail-closed default: any unmapped tool is treated as sensitive + irreversible,
// requiring explicit consent and a pro/admin actor.

const TOOL_POLICIES = {
    // ─── Filesystem ───────────────────────────────────────────────────────────
    'filesystem__read_file':               { actionType: 'files.read',   sensitive: false, irreversible: false },
    'filesystem__read_multiple_files':     { actionType: 'files.read',   sensitive: false, irreversible: false },
    'filesystem__list_directory':          { actionType: 'files.read',   sensitive: false, irreversible: false },
    'filesystem__directory_tree':          { actionType: 'files.read',   sensitive: false, irreversible: false },
    'filesystem__search_files':            { actionType: 'files.read',   sensitive: false, irreversible: false },
    'filesystem__get_file_info':           { actionType: 'files.read',   sensitive: false, irreversible: false },
    'filesystem__list_allowed_directories':{ actionType: 'files.read',   sensitive: false, irreversible: false },
    'filesystem__write_file':              { actionType: 'files.write',  sensitive: true,  irreversible: true  },
    'filesystem__edit_file':               { actionType: 'files.write',  sensitive: true,  irreversible: true  },
    'filesystem__create_directory':        { actionType: 'files.write',  sensitive: true,  irreversible: false },
    'filesystem__move_file':               { actionType: 'files.write',  sensitive: true,  irreversible: true  },

    // ─── Web fetch ────────────────────────────────────────────────────────────
    'fetch__fetch':                        { actionType: 'web.fetch',    sensitive: false, irreversible: false },
    'fetch__get':                          { actionType: 'web.fetch',    sensitive: false, irreversible: false },

    // ─── Tavily Search ────────────────────────────────────────────────────────
    'search__tavily-search':               { actionType: 'web.search',   sensitive: false, irreversible: false },
    'search__tavily-extract':              { actionType: 'web.fetch',    sensitive: false, irreversible: false },

    // ─── GitHub ───────────────────────────────────────────────────────────────
    'github__get_file_contents':           { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__search_repositories':         { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__search_code':                 { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__search_issues':               { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__search_commits':              { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__list_commits':                { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__list_branches':               { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__list_issues':                 { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__list_pull_requests':          { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__get_issue':                   { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__get_pull_request':            { actionType: 'github.read',  sensitive: false, irreversible: false },
    'github__create_issue':                { actionType: 'github.write', sensitive: true,  irreversible: false },
    'github__create_pull_request':         { actionType: 'github.write', sensitive: true,  irreversible: false },
    'github__push_files':                  { actionType: 'github.write', sensitive: true,  irreversible: true  },
    'github__create_branch':               { actionType: 'github.write', sensitive: true,  irreversible: false },
    'github__add_issue_comment':           { actionType: 'github.write', sensitive: true,  irreversible: false },
    'github__merge_pull_request':          { actionType: 'github.write', sensitive: true,  irreversible: true  },
    'github__update_issue':                { actionType: 'github.write', sensitive: true,  irreversible: false },

    // ─── PostgreSQL ───────────────────────────────────────────────────────────
    'postgres__query':                     { actionType: 'db.read',      sensitive: false, irreversible: false },

    // ─── Notion ───────────────────────────────────────────────────────────────
    'notion__API-get-self':                           { actionType: 'notion.read',  sensitive: false, irreversible: false },
    'notion__API-get-database':                       { actionType: 'notion.read',  sensitive: false, irreversible: false },
    'notion__API-post-database-query':                { actionType: 'notion.read',  sensitive: false, irreversible: false },
    'notion__API-get-page':                           { actionType: 'notion.read',  sensitive: false, irreversible: false },
    'notion__API-get-block-children':                 { actionType: 'notion.read',  sensitive: false, irreversible: false },
    'notion__API-search':                             { actionType: 'notion.read',  sensitive: false, irreversible: false },
    'notion__API-post-page':                          { actionType: 'notion.write', sensitive: true,  irreversible: false },
    'notion__API-patch-page':                         { actionType: 'notion.write', sensitive: true,  irreversible: false },
    'notion__API-patch-block-children':               { actionType: 'notion.write', sensitive: true,  irreversible: false },
    'notion__API-delete-block':                       { actionType: 'notion.write', sensitive: true,  irreversible: true  },

    // ─── Google Calendar ─────────────────────────────────────────────────────
    'gcal__list-calendars':                { actionType: 'calendar.read',  sensitive: false, irreversible: false },
    'gcal__list-events':                   { actionType: 'calendar.read',  sensitive: false, irreversible: false },
    'gcal__get-event':                     { actionType: 'calendar.read',  sensitive: false, irreversible: false },
    'gcal__search-events':                 { actionType: 'calendar.read',  sensitive: false, irreversible: false },
    'gcal__create-event':                  { actionType: 'calendar.write', sensitive: true,  irreversible: false },
    'gcal__update-event':                  { actionType: 'calendar.write', sensitive: true,  irreversible: false },
    'gcal__delete-event':                  { actionType: 'calendar.write', sensitive: true,  irreversible: true  },

    // ─── Supabase / Database ──────────────────────────────────────────────────
    'supabase__list_tables':               { actionType: 'db.read',      sensitive: false, irreversible: false },
    'supabase__list_projects':             { actionType: 'db.read',      sensitive: false, irreversible: false },
    'supabase__execute_sql':               { actionType: 'db.write',     sensitive: true,  irreversible: true  },
    'supabase__apply_migration':           { actionType: 'db.write',     sensitive: true,  irreversible: true  },
    'supabase__get_logs':                  { actionType: 'db.read',      sensitive: false, irreversible: false },
};

const FAIL_CLOSED_POLICY = {
    actionType: 'mcp.unknown',
    sensitive: true,
    irreversible: true,
};

function getPolicy(namespacedToolName) {
    return TOOL_POLICIES[namespacedToolName] || FAIL_CLOSED_POLICY;
}

module.exports = { getPolicy, TOOL_POLICIES, FAIL_CLOSED_POLICY };
