INSERT INTO config.upgrade_log (version) VALUES ('0416'); -- Scott McKellar

\qecho No transaction.  Renaming two indexes to correct spelling.
\qecho If either change fails, then the index was probably created
\qecho correctly in the first place; ignore the failure.

ALTER INDEX config.rule_recuring_fine_name_key
	RENAME TO rule_recurring_fine_name_key;

ALTER INDEX config.rule_recuring_fine_pkey
	RENAME TO rule_recurring_fine_pkey;
