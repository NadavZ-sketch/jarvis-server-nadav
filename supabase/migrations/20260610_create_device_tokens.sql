-- Push notification device tokens
-- Each registered mobile device stores its FCM/APNS token here.
-- The server reads all tokens when broadcasting and prunes stale ones.

CREATE TABLE IF NOT EXISTS device_tokens (
    token        TEXT        NOT NULL,
    platform     TEXT        NOT NULL DEFAULT 'android',
    app_version  TEXT,
    last_seen    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT device_tokens_pkey PRIMARY KEY (token)
);

COMMENT ON TABLE  device_tokens              IS 'FCM/APNS device tokens for push notifications';
COMMENT ON COLUMN device_tokens.token        IS 'FCM registration token or APNS device token';
COMMENT ON COLUMN device_tokens.platform     IS 'android | ios';
COMMENT ON COLUMN device_tokens.app_version  IS 'Client app version at registration time';
COMMENT ON COLUMN device_tokens.last_seen    IS 'Last successful push or re-registration timestamp';
