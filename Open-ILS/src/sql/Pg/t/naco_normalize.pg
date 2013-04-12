BEGIN;

SELECT plan(25);

CREATE FUNCTION nfkd(TEXT) RETURNS TEXT AS $$
    use strict;
    use warnings;
    use Unicode::Normalize;
    my $str = shift;
    return NFKD($str);
$$ LANGUAGE PLPERLU STABLE;

SELECT is( public.naco_normalize('abc'), 'abc', 'regular text' );
SELECT is( public.naco_normalize('ABC'), 'abc', 'regular text' );
SELECT is( public.naco_normalize('åbçdéñœöîøæÇıÂÅÍÎÏÔÔÒÚÆŒè'), 'abcdenoeoioaeciaaiiiooouaeoee', 'European diacritics' );
SELECT is( public.naco_normalize('“‘„«quotes»’”'), 'quotes', 'special quotes' );
SELECT is( public.naco_normalize('abc def'), 'def', 'special non-filing characters designation' );
SELECT is( public.naco_normalize('abcdef'), 'abcdef', 'unpaired start of string' );
SELECT is( public.naco_normalize('ß'), 'ss', 'sharp S (eszett)' );
SELECT is( public.naco_normalize('ﬂﬁﬀ'), 'flfiff', 'ligatures' );
SELECT is( public.naco_normalize('ƠơƯư²Ĳĳ'), 'oouu2ijij', 'NFKD applied correctly' );
SELECT is( public.naco_normalize('ÆØÞæðøþĐđıŁłŒœʻʼℓ'), 'aeothaedothddilloeoel', 'part 3.6' );
SELECT is( public.naco_normalize('Ð'), 'd', 'uppercase eth (missing from 3.6?)' );
SELECT is( public.naco_normalize('ıİ'), 'ii', 'Turkish I' );
SELECT is( public.naco_normalize('[book''s cover]'), 'books cover', 'square brackets and apostrophe' );
SELECT is( public.naco_normalize('  grue   food '), 'grue food', 'trim spaces' );
-- note addition of nfkd() to transform expected output
SELECT is( public.naco_normalize('한국어 조선말'), nfkd('한국어 조선말'), 'Korean text' );
SELECT is( public.naco_normalize('普通話 / 普通话'), '普通話 普通话', 'Chinese text' );
SELECT is( public.naco_normalize('العربية'), 'العربية', 'Arabic text' );
SELECT is( public.naco_normalize('ქართული ენა'), 'ქართული ენა', 'Georgian text' );
SELECT is( public.naco_normalize('русский язык'), 'русскии язык', 'Russian text' );
SELECT is( public.naco_normalize(E'\r\npa\tper\f'), 'paper', 'other whitespace' );
SELECT is( public.naco_normalize('#1: ∃ C++, @ home & abroad'), '#1 c++ @ home & abroad', 'other punctuation' );
SELECT is( public.naco_normalize('٠١٢٣٤٥'), '012345', 'other decimal digits' );
SELECT is( public.naco_normalize('²³¹'), '231', 'superscript numbers' );
SELECT is( public.naco_normalize('♭©®♯'), '♭ ♯', 'other symbols' );

SELECT is( public.naco_normalize('Smith, Jane. Poet, painter, and author', 'a'), 'smith, jane poet painter and author',
      'retain first comma' );

SELECT * FROM finish();

ROLLBACK;
