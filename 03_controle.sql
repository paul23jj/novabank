-- 03_controle.sql : si tout est cohérent, chaque requête retourne 0 ligne
SET ROLE bank_owner;

-- a. aucun solde négatif
SELECT account_id FROM core.accounts WHERE balance < 0;

-- b. le solde du compte = somme des écritures
SELECT a.account_id
FROM core.accounts a
JOIN (SELECT account_id,
             sum(CASE WHEN tx_type IN ('DEPOSIT','TRANSFER_IN') THEN amount ELSE -amount END) AS s
      FROM core.transactions GROUP BY account_id) t USING (account_id)
WHERE a.balance <> t.s;

-- c. chaque virement a exactement 2 écritures
SELECT transfer_id FROM core.transactions
WHERE transfer_id IS NOT NULL
GROUP BY transfer_id HAVING count(*) <> 2;

-- d. balance_after = balance_after précédent ± montant
SELECT tx_id FROM (
    SELECT tx_id, balance_after,
           coalesce(lag(balance_after) OVER (PARTITION BY account_id ORDER BY tx_id), 0)
           + CASE WHEN tx_type IN ('DEPOSIT','TRANSFER_IN') THEN amount ELSE -amount END AS attendu
    FROM core.transactions) x
WHERE balance_after <> attendu;
