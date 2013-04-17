SELECT evergreen.upgrade_deps_block_check('0789', :eg_version);

-- These can and should be run outside of a transaction
CREATE TEXT SEARCH CONFIGURATION title ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION author ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION subject ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION series ( COPY = english_nostop );
CREATE TEXT SEARCH CONFIGURATION identifier ( COPY = english_nostop );
