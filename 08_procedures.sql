-- 08_procedures.sql : virement sûr, ouverture de compte, relevé
-- À lancer en tant que postgres, dans bankdb, après 07_triggers.sql.
\set ON_ERROR_STOP on
SET ROLE bank_owner;

CREATE SEQUENCE IF NOT EXISTS core.seq_iban START 100000;   -- au-dessus des IBAN générés en 02

-- 1. Virement : une seule transaction, tout est annulé si une ligne échoue
CREATE OR REPLACE PROCEDURE core.sp_virement(
    p_from bigint, p_to bigint, p_amount numeric, p_label text,
    INOUT p_transfer_id bigint DEFAULT NULL)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_from core.accounts%ROWTYPE;
    v_to   core.accounts%ROWTYPE;
BEGIN
    -- 1. Vérifier les entrées
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Montant invalide : il doit être strictement positif';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
        RAISE EXCEPTION 'Comptes invalides : il faut deux comptes différents';
    END IF;

    -- 2. Verrouiller les 2 comptes TOUJOURS dans l'ordre des identifiants :
    --    deux virements croisés (A vers B, B vers A) ne peuvent donc jamais s'interbloquer
    PERFORM 1 FROM core.accounts WHERE account_id IN (p_from, p_to) ORDER BY account_id FOR UPDATE;

    SELECT * INTO v_from FROM core.accounts WHERE account_id = p_from;
    IF NOT FOUND THEN RAISE EXCEPTION 'Compte émetteur % introuvable', p_from; END IF;
    SELECT * INTO v_to FROM core.accounts WHERE account_id = p_to;
    IF NOT FOUND THEN RAISE EXCEPTION 'Compte destinataire % introuvable', p_to; END IF;
    IF v_from.status <> 'ACTIVE' THEN RAISE EXCEPTION 'Compte émetteur % non actif', p_from; END IF;
    IF v_to.status   <> 'ACTIVE' THEN RAISE EXCEPTION 'Compte destinataire % non actif', p_to; END IF;
    IF v_from.balance < p_amount THEN RAISE EXCEPTION 'Solde insuffisant sur le compte %', p_from; END IF;

    -- 3. Écrire : les triggers calculent les soldes et balance_after, et contrôlent les 2 écritures
    INSERT INTO core.transfers (from_account_id, to_account_id, amount, label)
    VALUES (p_from, p_to, p_amount, p_label)
    RETURNING transfer_id INTO p_transfer_id;

    INSERT INTO core.transactions (account_id, tx_type, amount, transfer_id)
    VALUES (p_from, 'TRANSFER_OUT', p_amount, p_transfer_id),
           (p_to,   'TRANSFER_IN',  p_amount, p_transfer_id);
END;
$$;

-- 2. Ouverture d'un compte (client vérifié seulement), avec dépôt initial facultatif
CREATE OR REPLACE PROCEDURE core.sp_ouvrir_compte(
    p_customer_id bigint,
    p_type core.account_type DEFAULT 'CHECKING',
    p_deposit numeric DEFAULT 0,
    INOUT p_account_id bigint DEFAULT NULL)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_kyc core.kyc_status;
BEGIN
    IF p_deposit IS NULL OR p_deposit < 0 THEN
        RAISE EXCEPTION 'Dépôt initial invalide';
    END IF;
    SELECT kyc_status INTO v_kyc FROM core.customers WHERE customer_id = p_customer_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Client % introuvable', p_customer_id;
    END IF;
    IF v_kyc <> 'VERIFIED' THEN
        RAISE EXCEPTION 'Client % non vérifié (KYC : %)', p_customer_id, v_kyc;
    END IF;

    INSERT INTO core.accounts (customer_id, iban, account_type)
    VALUES (p_customer_id, 'FR76' || lpad(nextval('core.seq_iban')::text, 23, '0'), p_type)
    RETURNING account_id INTO p_account_id;

    IF p_deposit > 0 THEN
        INSERT INTO core.transactions (account_id, tx_type, amount)
        VALUES (p_account_id, 'DEPOSIT', p_deposit);   -- le trigger met le solde à jour
    END IF;
END;
$$;

-- 3. Relevé : renvoie un curseur (à lire avec FETCH, dans une transaction)
CREATE OR REPLACE PROCEDURE core.sp_releve(
    p_account_id bigint, p_from timestamptz, p_to timestamptz,
    INOUT p_cursor refcursor DEFAULT 'curs_releve')
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.accounts WHERE account_id = p_account_id) THEN
        RAISE EXCEPTION 'Compte % introuvable', p_account_id;
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_from >= p_to THEN
        RAISE EXCEPTION 'Période invalide';
    END IF;
    OPEN p_cursor FOR
        SELECT tx_id, created_at, tx_type, amount, balance_after
        FROM core.transactions
        WHERE account_id = p_account_id AND created_at >= p_from AND created_at < p_to
        ORDER BY created_at DESC, tx_id DESC;
END;
$$;

-- L'appli n'a aucun droit sur les tables : seulement ces procédures
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA core TO bank_app;
