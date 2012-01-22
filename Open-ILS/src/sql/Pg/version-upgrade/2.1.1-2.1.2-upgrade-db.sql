-- Fix sorting by pubdate by ensuring migrated records
-- have a pubdate attribute in metabib.record_attr.attrs
UPDATE metabib.record_attr
   SET attrs = attrs || ('pubdate' => (attrs->'date1'))
   WHERE defined(attrs, 'pubdate') IS FALSE
   AND defined(attrs, 'date1') IS TRUE;
