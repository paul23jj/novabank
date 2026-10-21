-- 90_tests.sql : tests des triggers (E6) et des procédures (E7)
-- À lancer en tant que postgres : sudo -u postgres psql -d bankdb < 90_tests.sql
\set ON_ERROR_STOP off
\set ECHO queries
\pset pager off
SET ROLE bank_owner;

-- Deux comptes actifs bien approvisionnés
SELECT account_id AS acc  FROM core.accounts WHERE status = 'ACTIVE' ORDER BY balance DESC LIMIT 1 \gset
SELECT account_id AS acc2 FROM core.accounts WHERE status = 'ACTIVE' ORDER BY balance DESC OFFSET 1 LIMIT 1 \gset

\echo '=== E6.1 Le solde se met à jour seul (OK) ==='
SELECT balance FROM core.accounts WHERE account_id = :acc;
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (:acc, 'DEPOSIT', 100) RETURNING tx_id, balance_after;
SELECT balance FROM core.accounts WHERE account_id = :acc;
\echo '--- refusés : solde insuffisant, compte gelé'
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (:acc, 'WITHDRAWAL', 900000000);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (33, 'DEPOSIT', 10);

\echo '=== E6.2 Grand livre immuable (3 refus) ==='
UPDATE core.transactions SET amount = 1 WHERE tx_id = 1;
DELETE FROM core.transactions WHERE tx_id = 1;
TRUNCATE core.transactions, core.fraud_alerts;

\echo '=== E6.3 Fraude : retrait de 5 000 déclenche une alerte, 4 999,99 non ==='
SELECT count(*) AS alertes_avant FROM core.fraud_alerts;
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (:acc, 'WITHDRAWAL', 4999.99);
SELECT count(*) AS alertes_apres_4999 FROM core.fraud_alerts;
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (:acc, 'WITHDRAWAL', 5000) RETURNING tx_id;
SELECT alert_id, account_id, tx_id, rule_code, status FROM core.fraud_alerts ORDER BY alert_id DESC LIMIT 1;

\echo '=== E6.4 Audit : qui, quand, avant, après ==='
UPDATE core.accounts SET status = 'FROZEN' WHERE account_id = :acc2;
UPDATE core.accounts SET status = 'ACTIVE' WHERE account_id = :acc2;
SELECT log_id, table_name, operation, old_data->>'status' AS avant, new_data->>'status' AS apres, db_user, changed_at
FROM audit.audit_log ORDER BY log_id DESC LIMIT 2;

\echo '=== E6.5 Un virement = 2 écritures ou aucune (refus au COMMIT) ==='
BEGIN;
INSERT INTO core.transfers (from_account_id, to_account_id, amount) VALUES (:acc, :acc2, 5);
INSERT INTO core.transactions (account_id, tx_type, amount, transfer_id)
VALUES (:acc, 'TRANSFER_OUT', 5, (SELECT max(transfer_id) FROM core.transfers));
COMMIT;

\echo '=== E7.1 Virement réussi, par le profil bank_app ==='
SELECT account_id, balance FROM core.accounts WHERE account_id IN (:acc, :acc2) ORDER BY account_id;
SET ROLE bank_app;
CALL core.sp_virement(:acc, :acc2, 25.00, 'Test virement', NULL);
SET ROLE bank_owner;
SELECT tx_id, account_id, tx_type, amount, balance_after, transfer_id
FROM core.transactions WHERE transfer_id = (SELECT max(transfer_id) FROM core.transfers);

\echo '--- refusés : même compte, montant négatif, solde insuffisant, compte inconnu, compte gelé'
SET ROLE bank_app;
CALL core.sp_virement(:acc, :acc, 10, 'même compte', NULL);
CALL core.sp_virement(:acc, :acc2, -5, 'montant négatif', NULL);
CALL core.sp_virement(:acc, :acc2, 900000000, 'trop gros', NULL);
CALL core.sp_virement(:acc, 999999999, 10, 'compte inconnu', NULL);
CALL core.sp_virement(:acc, 33, 10, 'compte gelé', NULL);

\echo '=== E7.2 5 virements rapprochés : alerte BURST_TRANSFERS ==='
CALL core.sp_virement(:acc, :acc2, 1, 'rafale', NULL);
CALL core.sp_virement(:acc, :acc2, 1, 'rafale', NULL);
CALL core.sp_virement(:acc, :acc2, 1, 'rafale', NULL);
CALL core.sp_virement(:acc, :acc2, 1, 'rafale', NULL);
CALL core.sp_virement(:acc, :acc2, 1, 'rafale', NULL);
SET ROLE bank_owner;
SELECT alert_id, account_id, rule_code, status FROM core.fraud_alerts WHERE rule_code = 'BURST_TRANSFERS' ORDER BY alert_id DESC LIMIT 2;

\echo '=== E7.3 Ouverture de compte ==='
SELECT customer_id AS cid_ok FROM core.customers WHERE kyc_status = 'VERIFIED' ORDER BY customer_id LIMIT 1 \gset
SELECT customer_id AS cid_ko FROM core.customers WHERE kyc_status <> 'VERIFIED' ORDER BY customer_id LIMIT 1 \gset
SET ROLE bank_app;
CALL core.sp_ouvrir_compte(:cid_ok, 'SAVINGS', 500, NULL);
\echo '--- refusés : client non vérifié, client inconnu'
CALL core.sp_ouvrir_compte(:cid_ko, 'SAVINGS', 0, NULL);
CALL core.sp_ouvrir_compte(999999999, 'SAVINGS', 0, NULL);
SET ROLE bank_owner;
SELECT account_id, customer_id, iban, account_type, balance, status FROM core.accounts ORDER BY account_id DESC LIMIT 1;

\echo '=== E7.4 Relevé ==='
SET ROLE bank_app;
BEGIN;
CALL core.sp_releve(:acc, '2026-01-01', '2026-12-31');
FETCH 5 FROM curs_releve;
COMMIT;
\echo '--- refusé : compte inconnu'
CALL core.sp_releve(999999999, '2026-01-01', '2026-12-31');
RESET ROLE;
