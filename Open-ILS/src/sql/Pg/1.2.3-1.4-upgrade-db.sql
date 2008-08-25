/* Enable LIKE to use an index for database clusters with locales other than C or POSIX */
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (value text_pattern_ops);
