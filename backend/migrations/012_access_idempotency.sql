-- Request IDs make retrying member creation and token issuance safe after an
-- ambiguous network failure.  They are opaque client-generated values.
ALTER TABLE users ADD COLUMN request_id TEXT;
ALTER TABLE api_tokens ADD COLUMN request_id TEXT;

CREATE UNIQUE INDEX idx_users_request_id
ON users(request_id) WHERE request_id IS NOT NULL;

CREATE UNIQUE INDEX idx_api_tokens_request_id
ON api_tokens(request_id) WHERE request_id IS NOT NULL;
