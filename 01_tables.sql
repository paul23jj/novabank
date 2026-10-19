-- 01_tables.sql : schémas, types et 6 tables avec leurs protections
\set ON_ERROR_STOP on
SET ROLE bank_owner;   -- les objets appartiendront à bank_owner

CREATE SCHEMA core;
CREATE SCHEMA audit;

-- Listes fermées de valeurs
CREATE TYPE core.kyc_status     AS ENUM ('PENDING', 'VERIFIED', 'REJECTED');
CREATE TYPE core.account_type   AS ENUM ('CHECKING', 'SAVINGS');
CREATE TYPE core.account_status AS ENUM ('ACTIVE', 'FROZEN', 'CLOSED');
CREATE TYPE core.tx_type        AS ENUM ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER_OUT', 'TRANSFER_IN');
CREATE TYPE core.alert_status   AS ENUM ('OPEN', 'REVIEWED', 'CLOSED');

CREATE TABLE core.customers (
    customer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name  text NOT NULL,
    last_name   text NOT NULL,
    email       text NOT NULL,
    phone       text,
    birth_date  date NOT NULL,
    kyc_status  core.kyc_status NOT NULL DEFAULT 'PENDING',
    risk_level  smallint NOT NULL DEFAULT 1,     -- 1 = faible, 3 = élevé
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_customers_email UNIQUE (email),
    CONSTRAINT ck_customers_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT ck_customers_adult CHECK (birth_date <= (created_at::date - INTERVAL '18 years')::date),
    CONSTRAINT ck_customers_risk  CHECK (risk_level BETWEEN 1 AND 3)
);

CREATE TABLE core.accounts (
    account_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  bigint NOT NULL REFERENCES core.customers (customer_id),
    iban         text NOT NULL,
    account_type core.account_type NOT NULL DEFAULT 'CHECKING',
    balance      numeric(14,2) NOT NULL DEFAULT 0,
    status       core.account_status NOT NULL DEFAULT 'ACTIVE',
    opened_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_accounts_iban    UNIQUE (iban),
    CONSTRAINT ck_accounts_balance CHECK (balance >= 0),
    CONSTRAINT ck_accounts_iban    CHECK (iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$')
);

CREATE TABLE core.transfers (
    transfer_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_account_id bigint NOT NULL REFERENCES core.accounts (account_id),
    to_account_id   bigint NOT NULL REFERENCES core.accounts (account_id),
    amount          numeric(14,2) NOT NULL,
    label           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_transfers_amount CHECK (amount > 0),
    CONSTRAINT ck_transfers_diff   CHECK (from_account_id <> to_account_id)
);

CREATE TABLE core.transactions (
    tx_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id    bigint NOT NULL REFERENCES core.accounts (account_id),
    tx_type       core.tx_type NOT NULL,
    amount        numeric(14,2) NOT NULL,         -- toujours positif, le sens vient de tx_type
    balance_after numeric(14,2) NOT NULL,
    transfer_id   bigint REFERENCES core.transfers (transfer_id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_tx_amount        CHECK (amount > 0),
    CONSTRAINT ck_tx_balance_after CHECK (balance_after >= 0),
    CONSTRAINT ck_tx_transfer_link CHECK ((tx_type IN ('TRANSFER_OUT','TRANSFER_IN')) = (transfer_id IS NOT NULL))
);

CREATE TABLE core.fraud_alerts (
    alert_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES core.accounts (account_id),
    tx_id      bigint REFERENCES core.transactions (tx_id),
    rule_code  text NOT NULL,
    status     core.alert_status NOT NULL DEFAULT 'OPEN',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_alerts_rule CHECK (rule_code IN ('LARGE_WITHDRAWAL', 'BURST_TRANSFERS'))
);

CREATE TABLE audit.audit_log (
    log_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name text NOT NULL,
    operation  text NOT NULL,
    old_data   jsonb,
    new_data   jsonb,
    db_user    text NOT NULL DEFAULT current_user,
    changed_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_audit_operation CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE'))
);
