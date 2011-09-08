-- Evergreen DB patch XXXX.schema.generic-mapping-index-normalizer.sql
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0615', :eg_version);

-- evergreen.generic_map_normalizer 

CREATE OR REPLACE FUNCTION evergreen.generic_map_normalizer ( TEXT, TEXT ) RETURNS TEXT AS $f$
my $string = shift;
my %map;

my $default = $string;

$_ = shift;
while (/^\s*?(.*?)\s*?=>\s*?(\S+)\s*/) {
    if ($1 eq '') {
        $default = $2;
    } else {
        $map{$2} = [split(/\s*,\s*/, $1)];
    }
    $_ = $';
}

for my $key ( keys %map ) {
    return $key if (grep { $_ eq $string } @{ $map{$key} });
}

return $default;

$f$ LANGUAGE PLPERLU;

-- evergreen.generic_map_normalizer 

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
    'Generic Mapping Normalizer', 
    'Map values or sets of values to new values',
    'generic_map_normalizer', 
    1
);

COMMIT;
