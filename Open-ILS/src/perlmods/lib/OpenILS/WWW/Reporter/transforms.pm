#!/usr/bin/perl

package OpenILS::WWW::Reporter;

our $dtype_xform_map = {
        'int'                   => [ 'avg','stddev','sum','count','count_dist','numformat'],
        'numeric'       => [ 'avg','stddev','sum','count','count_dist','numformat'],
        'float' => [ 'avg','stddev','sum','count','count_dist','numformat'],
        'time'  => [ 'count', 'dateformat'],
        'date'  => [ 'count', 'age','dateformat'],
        'timestamp'     => [ 'count', 'age','dateformat'],
        'timestamptz'   => [ 'count', 'age','dateformat'],
        'text'  => [ 'count','count_dist','lower','upper','substr'],
        'call_number'  => [ 'count','count_dist','dewy','dewy_prefix','count_dist_dewey','count_dist_dewey_prefix','lower','upper','substr'],
};



our $dtype_xforms = {
        'avg'           => { 
                'name'  => 'Average per group',
                'select'        => 'AVG(?COLNAME?)',
                'group' => 0 },
        'stddev'        => {
                'label' => 'Standard Deviation per group',
                'select'        => 'STDDEV(?COLNAME?)',
                'group' => 0 },
        'sum'           => {
                'label' => 'Sum per group',
                'select'        => 'SUM(?COLNAME?)',
                'group' => 0 }, 
        'count'         => {    
                'label' => 'Count per group',
                'select'        => 'COUNT(?COLNAME?)',
                'group' => 0 },
        'count_dist'            => {
                'label' => 'Distinct Count per group',
                'select'        => 'COUNT(DISTINCT ?COLNAME?)',
                'group' => 0 }, 
        'count_dist_dewey'      => {
                'label' => 'Distinct Count of Dewey numbers per group',
                'select'        => 'COUNT(DISTINCT call_number_dewey(?COLNAME?))',
                'group' => 1 }, 
        'count_dist_dewey_prefix'=> {
                'label' => 'Distinct Count of Dewey Number Prefixes per group',
                'select'        => 'COUNT(DISTINCT call_number_dewey(?COLNAME?,?PARAM?))',
                'param' => 1,           
                'group' => 1 }, 
        'dewy_prefix'         => {    
                'label' => 'Extract Dewey number prefix from call number',
                'select'        => 'call_number_dewey(?COLNAME?,?PARAM?)',
                'param' => 1,           
                'group' => 1 },
        'dewy'         => {    
                'label' => 'Extract Dewey number from call number',
                'select'        => 'call_number_dewey(?COLNAME?)',
                'group' => 1 },
        'lower'         => {    
                'label' => 'Transform string to lower case',
                'select'        => 'LOWER(?COLNAME?)',
                'group' => 1 },
        'upper'         => {
                'label' => 'Transform string to upper case',
                'select'        => 'UPPER(?COLNAME?)',
                'group' => 1 }, 
        'substr'                => {
                'label' => 'Trim string length',
                'select'        => 'substr(?COLNAME?,1,?PARAM?)',
                'param' => 1,           
                'group' => 1 },                 
        'age'           => {            
                'label' => 'Age as of runtime -- day granularity',
                'select'        => 'AGE(?COLNAME?::DATE)',
                'group' => 1 },
        'dateformat'            => { # see http://www.postgresql.org/docs/8.0/interactive/functions-formatting.html
                'label' => 'Format date and time',
                'select'        => "TO_CHAR(?COLNAME?,'?PARAM?')",
                'param' => 1,           
                'group' => 1 },                 
        'numformat'             => { # see http://www.postgresql.org/docs/8.0/interactive/functions-formatting.html
                'label' => 'Format Numeric data',
                'select'        => "TO_CHAR(?COLNAME?,'?PARAM?')",
                'param' => 1,                           
                'group' => 1 },                         
};                                      

;
