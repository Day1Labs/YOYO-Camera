-- Users table for Apple Sign In
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    apple_user_id TEXT UNIQUE NOT NULL,
    email TEXT,
    full_name TEXT,
    credits INTEGER DEFAULT 3,
    subscription_status INTEGER DEFAULT 0, -- 0: free, 1: pro
    subscription_end_date TEXT, -- ISO8601 format
    original_transaction_id TEXT, -- Prevents subscription sharing across accounts
    last_transaction_id TEXT, -- To track monthly credit reset
    last_credit_reset_date TEXT DEFAULT (datetime('now')),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_users_apple_user_id ON users(apple_user_id);
CREATE INDEX IF NOT EXISTS idx_users_original_txn_id ON users(original_transaction_id);

-- Shared automation rules table
CREATE TABLE IF NOT EXISTS shared_automation_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    rule_json TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_shared_rules_code ON shared_automation_rules(code);