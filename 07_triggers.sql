-- 07_triggers.sql : solde automatique, grand livre immuable, 2 écritures par virement, fraude, audit
-- À lancer en tant que postgres, dans bankdb, APRÈS le chargement des données (02).
\set ON_ERROR_STOP on
SET ROLE bank_owner;

-- 1. Le solde se met à jour seul (BEFORE INSERT sur le grand livre)
CREATE OR REPLACE FUNCTION core.fn_tx_balance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_balance numeric(14,2);
    v_status  core.account_status;
BEGIN
    -- FOR UPDATE verrouille le compte : une 2e opération simultanée attend ici sa fin,
    -- donc elle lit le solde à jour (impossible d'avoir deux lectures du même solde)
    SELECT balance, status INTO v_balance, v_status
    FROM core.accounts WHERE account_id = NEW.account_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compte % introuvable', NEW.account_id;
    END IF;
    IF v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Compte % non actif (statut %)', NEW.account_id, v_status;
    END IF;
    IF NEW.tx_type IN ('DEPOSIT', 'TRANSFER_IN') THEN
        v_balance := v_balance + NEW.amount;
    ELSE
        v_balance := v_balance - NEW.amount;
    END IF;
    IF v_balance < 0 THEN
        RAISE EXCEPTION 'Solde insuffisant sur le compte %', NEW.account_id;
    END IF;
    UPDATE core.accounts SET balance = v_balance WHERE account_id = NEW.account_id;
    NEW.balance_after := v_balance;
    RETURN NEW;   -- sans ce RETURN NEW, l'écriture serait annulée sans erreur
END;
$$;

DROP TRIGGER IF EXISTS trg_transactions_before_insert_balance ON core.transactions;
CREATE TRIGGER trg_transactions_before_insert_balance
    BEFORE INSERT ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_tx_balance();

-- 2. Le grand livre est immuable : 3 événements (UPDATE, DELETE par ligne, TRUNCATE par instruction)
CREATE OR REPLACE FUNCTION core.fn_ledger_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Grand livre immuable : % interdit sur %.%', TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$$;

DROP TRIGGER IF EXISTS trg_transactions_before_updel_immutable ON core.transactions;
CREATE TRIGGER trg_transactions_before_updel_immutable
    BEFORE UPDATE OR DELETE ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_ledger_immutable();

DROP TRIGGER IF EXISTS trg_transactions_before_truncate_immutable ON core.transactions;
CREATE TRIGGER trg_transactions_before_truncate_immutable
    BEFORE TRUNCATE ON core.transactions
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_ledger_immutable();

-- 3. Un virement = 2 écritures ou aucune (vérifié au COMMIT grâce à DEFERRED)
CREATE OR REPLACE FUNCTION core.fn_tx_two_entries() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT count(*) FROM core.transactions WHERE transfer_id = NEW.transfer_id) <> 2 THEN
        RAISE EXCEPTION 'Le virement % doit avoir exactement 2 écritures', NEW.transfer_id;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_transactions_after_insert_two_entries ON core.transactions;
CREATE CONSTRAINT TRIGGER trg_transactions_after_insert_two_entries
    AFTER INSERT ON core.transactions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW WHEN (NEW.transfer_id IS NOT NULL)
    EXECUTE FUNCTION core.fn_tx_two_entries();

-- 4. Fraude : retrait de 5 000 ou plus, ou 5 virements sortants en 10 minutes
CREATE OR REPLACE FUNCTION core.fn_tx_fraud() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_nb integer;
BEGIN
    IF NEW.tx_type = 'WITHDRAWAL' AND NEW.amount >= 5000 THEN
        INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
        VALUES (NEW.account_id, NEW.tx_id, 'LARGE_WITHDRAWAL');
    END IF;
    IF NEW.tx_type = 'TRANSFER_OUT' THEN
        SELECT count(*) INTO v_nb
        FROM core.transactions
        WHERE account_id = NEW.account_id
          AND tx_type = 'TRANSFER_OUT'
          AND created_at >  NEW.created_at - INTERVAL '10 minutes'
          AND created_at <= NEW.created_at;
        IF v_nb >= 5 THEN
            INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
            VALUES (NEW.account_id, NEW.tx_id, 'BURST_TRANSFERS');
        END IF;
    END IF;
    RETURN NULL;   -- trigger AFTER : on rend NULL
END;
$$;

DROP TRIGGER IF EXISTS trg_transactions_after_insert_fraud ON core.transactions;
CREATE TRIGGER trg_transactions_after_insert_fraud
    AFTER INSERT ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_tx_fraud();

-- 5. Audit : une seule fonction pour plusieurs tables (TG_TABLE_NAME, TG_OP, to_jsonb)
--    SECURITY DEFINER : elle écrit dans audit_log même si l'utilisateur n'a aucun droit dessus
CREATE OR REPLACE FUNCTION core.fn_audit() RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
    INSERT INTO audit.audit_log (table_name, operation, old_data, new_data, db_user)
    VALUES (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, TG_OP,
            CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END,
            session_user::text);
    RETURN NULL;
END;
$$;

-- Comptes : création, suppression, et seulement les changements importants (pas le solde)
DROP TRIGGER IF EXISTS trg_accounts_after_insdel_audit ON core.accounts;
CREATE TRIGGER trg_accounts_after_insdel_audit
    AFTER INSERT OR DELETE ON core.accounts
    FOR EACH ROW EXECUTE FUNCTION core.fn_audit();
DROP TRIGGER IF EXISTS trg_accounts_after_update_audit ON core.accounts;
CREATE TRIGGER trg_accounts_after_update_audit
    AFTER UPDATE ON core.accounts
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status
       OR OLD.customer_id IS DISTINCT FROM NEW.customer_id
       OR OLD.iban IS DISTINCT FROM NEW.iban)
    EXECUTE FUNCTION core.fn_audit();

-- Clients : création, suppression, changement d'email, de KYC ou de niveau de risque
DROP TRIGGER IF EXISTS trg_customers_after_insdel_audit ON core.customers;
CREATE TRIGGER trg_customers_after_insdel_audit
    AFTER INSERT OR DELETE ON core.customers
    FOR EACH ROW EXECUTE FUNCTION core.fn_audit();
DROP TRIGGER IF EXISTS trg_customers_after_update_audit ON core.customers;
CREATE TRIGGER trg_customers_after_update_audit
    AFTER UPDATE ON core.customers
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email
       OR OLD.kyc_status IS DISTINCT FROM NEW.kyc_status
       OR OLD.risk_level IS DISTINCT FROM NEW.risk_level)
    EXECUTE FUNCTION core.fn_audit();
