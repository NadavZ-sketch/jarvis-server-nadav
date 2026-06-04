-- Portable app/web settings (AI, voice, appearance, today, notifications, advanced)
-- stored as a single JSONB blob so they survive device reinstalls and sync across
-- devices. Identity fields (user_name/assistant_name/gender/personality) keep their
-- dedicated columns; everything portable lives here.
-- Keys are written by AppSettings.toPreferences() (Flutter) and the settings blob in
-- progress-map.html, and shallow-merged server-side in POST /user-profile.
alter table user_profiles
  add column if not exists preferences jsonb not null default '{}'::jsonb;
