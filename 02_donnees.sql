-- 02_donnees.sql : 10 000 clients, 15 000 comptes, 250 000 virements, 1 000 000 d'écritures
-- À lancer en tant que postgres, avant la création des triggers (E6).
\set ON_ERROR_STOP on
\timing on
SET ROLE bank_owner;
SELECT setseed(0.42);   -- mêmes données à chaque lancement

-- Remise à zéro : le script peut être relancé
TRUNCATE core.fraud_alerts, core.transactions, core.transfers,
         core.accounts, core.customers RESTART IDENTITY;

-- 1. Clients (10 000), tous majeurs : naissance = 18 ans + 0 à 50 ans avant la création
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date,
                            kyc_status, risk_level, created_at)
SELECT fn, ln,
       lower(fn || '.' || ln || g || '@example.com'),
       '06' || lpad(g::text, 8, '0'),
       (ts::date - INTERVAL '18 years')::date - (random() * 18250)::int,
       (ARRAY['PENDING','VERIFIED','VERIFIED','VERIFIED','REJECTED'])
           [1 + floor(random() * 5)::int]::core.kyc_status,
       (ARRAY[1,1,1,1,1,2,2,3])[1 + floor(random() * 8)::int],
       ts
FROM (
    SELECT g,
           (ARRAY['Lucas','Emma','Hugo','Lea','Louis','Chloe','Jules','Manon','Adam','Sarah'])[1 + g % 10] AS fn,
           (ARRAY['Martin','Bernard','Dubois','Thomas','Robert','Richard','Petit','Durand','Leroy','Moreau'])[1 + (g / 10) % 10] AS ln,
           timestamptz '2023-01-01' + random() * interval '365 days' AS ts
    FROM generate_series(1, 10000) AS g
) s;

-- 2. Comptes (15 000) : 1 ou 2 par client, environ 3 % gelés
INSERT INTO core.accounts (customer_id, iban, account_type, status, opened_at)
SELECT 1 + (g - 1) % 10000,
       'FR76' || lpad(g::text, 23, '0'),
       (CASE WHEN g % 4 = 0 THEN 'SAVINGS' ELSE 'CHECKING' END)::core.account_type,
       (CASE WHEN g % 33 = 0 THEN 'FROZEN' ELSE 'ACTIVE' END)::core.account_status,
       timestamptz '2024-01-01' + random() * interval '180 days'
FROM generate_series(1, 15000) AS g;

-- 3. Virements (250 000) : le compte destinataire est décalé de 1 à 14 999 rangs
--    (modulo 15 000), donc jamais le même que l'émetteur
INSERT INTO core.transfers (from_account_id, to_account_id, amount, label, created_at)
SELECT f,
       1 + (f - 1 + d) % 15000,
       round((5 + random() * 1995)::numeric, 2),
       'Virement ' || g,
       ts
FROM (
    SELECT g,
           1 + floor(random() * 15000)::int AS f,
           1 + floor(random() * 14999)::int AS d,
           timestamptz '2024-07-01' + random() * interval '800 days' AS ts
    FROM generate_series(1, 250000) AS g
) s;

-- 4. Toutes les écritures dans une table temporaire
CREATE TEMP TABLE ops (
    ord         bigint GENERATED ALWAYS AS IDENTITY,   -- départage les égalités de date
    account_id  bigint NOT NULL,
    tx_type     core.tx_type NOT NULL,
    amount      numeric(14,2) NOT NULL,
    transfer_id bigint,
    created_at  timestamptz NOT NULL
);

-- 4a. 2 écritures par virement (sortie et entrée, même date)
INSERT INTO ops (account_id, tx_type, amount, transfer_id, created_at)
SELECT from_account_id, 'TRANSFER_OUT'::core.tx_type, amount, transfer_id, created_at FROM core.transfers
UNION ALL
SELECT to_account_id,   'TRANSFER_IN'::core.tx_type,  amount, transfer_id, created_at FROM core.transfers;

-- 4b. 485 000 dépôts (60 %) et retraits (40 %), dont de rares gros retraits (≥ 5 000)
INSERT INTO ops (account_id, tx_type, amount, created_at)
SELECT 1 + floor(random() * 15000)::int,
       (CASE WHEN r < 0.6 THEN 'DEPOSIT' ELSE 'WITHDRAWAL' END)::core.tx_type,
       CASE WHEN r < 0.6   THEN round((10 + random() * 2990)::numeric, 2)
            WHEN r < 0.995 THEN round((10 + random() * 790)::numeric, 2)
            ELSE                round((5000 + random() * 4000)::numeric, 2) END,
       timestamptz '2024-07-01' + random() * interval '800 days'
FROM (SELECT random() AS r FROM generate_series(1, 485000)) s;

-- 4c. Dépôt d'ouverture de chaque compte = total de ses débits + un extra.
--     Il est daté de l'ouverture du compte, donc avant toute autre opération.
INSERT INTO ops (account_id, tx_type, amount, created_at)
SELECT a.account_id,
       'DEPOSIT'::core.tx_type,
       coalesce(d.total, 0) + round((100 + random() * 1900)::numeric, 2),
       a.opened_at
FROM core.accounts a
LEFT JOIN (SELECT account_id, sum(amount) AS total
           FROM ops
           WHERE tx_type IN ('WITHDRAWAL', 'TRANSFER_OUT')
           GROUP BY account_id) d USING (account_id);

-- 5. Grand livre, trié par date ; balance_after = solde cumulé par compte (fonction de fenêtre)
INSERT INTO core.transactions (account_id, tx_type, amount, balance_after, transfer_id, created_at)
SELECT account_id, tx_type, amount,
       sum(CASE WHEN tx_type IN ('DEPOSIT', 'TRANSFER_IN') THEN amount ELSE -amount END)
           OVER (PARTITION BY account_id ORDER BY created_at, ord),
       transfer_id, created_at
FROM ops
ORDER BY created_at, ord;

-- 6. Solde de chaque compte = dernière valeur de balance_after
UPDATE core.accounts a
SET balance = l.balance_after
FROM (SELECT DISTINCT ON (account_id) account_id, balance_after
      FROM core.transactions
      ORDER BY account_id, tx_id DESC) l
WHERE a.account_id = l.account_id;

ANALYZE core.customers, core.accounts, core.transfers, core.transactions;

-- 7. Comptages
SELECT 'customers' AS table_name, count(*) FROM core.customers
UNION ALL SELECT 'accounts',     count(*) FROM core.accounts
UNION ALL SELECT 'transfers',    count(*) FROM core.transfers
UNION ALL SELECT 'transactions', count(*) FROM core.transactions;
