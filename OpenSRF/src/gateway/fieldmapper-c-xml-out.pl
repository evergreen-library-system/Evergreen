#!/usr/bin/perl
use strict; use warnings;
use lib '../../../Open-ILS/src/perlmods/';
use lib '../perlmods/';
use OpenILS::Utils::Fieldmapper;  


if(!$ARGV[1]) {
	print "usage: $0 <header_file> <source_file>\n";
	exit;
}

warn "Generating fieldmapper-c code...\n";


print $ARGV[0] . "\n";
print $ARGV[1] . "\n";

open(HEADER, ">$ARGV[0]");
open(SOURCE, ">$ARGV[1]");


warn "Generating fieldmapper-c code...\n";

my $map = $Fieldmapper::fieldmap;

print HEADER <<C;
#ifndef _TOXML_H_
#define _TOXML_H_

char* json_string_to_xml(char*);

#endif
C

print SOURCE <<C;

#include <string.h>

/* and the JSON parser, so we can read the response we're XMLizing */
#include <string.h>
#include "objson/object.h"
#include "objson/json_parser.h"
#include "opensrf/utils.h"

char* json_string_to_xml(char*);
void _rest_xml_output(growing_buffer*, object*, char*, int);
char * _lookup_fm_field(char*,int);

char* json_string_to_xml(char* content) {
	object * obj;
	growing_buffer * res_xml;
	char * output;
	int i;

	obj = json_parse_string( content );
	res_xml = buffer_init(1024);

	if (!obj)
		return NULL;
	
	buffer_add(res_xml, "<response>");

	for( i = 0; i!= obj->size; i++ ) {
		_rest_xml_output(res_xml, obj->get_index(obj,i), NULL, 0);
	}

	buffer_add(res_xml, "</response>");

	output = buffer_data(res_xml);
	buffer_free(res_xml);

	return output;
}

void _rest_xml_output(growing_buffer* buf, object* obj, char * fm_class, int fm_index) {
	char * tag;
	int i;
	

	if(fm_class) {
		tag = _lookup_fm_field(fm_class,fm_index);
	} else {
		tag = strdup("datum");
	}
        
        /* add class hints if we have a class name */
        if(obj->classname) {
        	if(obj->is_null) {
			buffer_fadd(buf,"<%s><Object class_hint=\\\"%s\\\"/></%s>", tag, obj->classname, tag);
			return;
		} else {
			buffer_fadd(buf,"<%s><Object class_hint=\\\"%s\\\">", tag, obj->classname);
		}
	}

	/* now add the data */
	if(obj->is_null)
		buffer_fadd(buf, "<%s/>",tag);
                
	else if(obj->is_bool && obj->bool_value) {
		if (obj->classname)
			buffer_add(buf, "true");
		else
			buffer_fadd(buf, "<%s>true</%s>",tag,tag);
                
	} else if(obj->is_bool && ! obj->bool_value) {
		if (obj->classname)
			buffer_add(buf, "false");
		else
			buffer_fadd(buf, "<%s>false</%s>",tag,tag);

	} else if (obj->is_string) {
		if (obj->classname)
			buffer_add(buf,obj->string_data);
		else
			buffer_fadd(buf,"<%s>%s</%s>",tag,obj->string_data,tag);

	} else if(obj->is_number) {
		if (obj->classname)
			buffer_fadd(buf,"%ld",obj->num_value);
		else
			buffer_fadd(buf,"<%s>%ld</%s>",tag,obj->num_value,tag);

	} else if(obj->is_double) {
		if (obj->classname)
			buffer_fadd(buf,"%lf",tag,obj->double_value,tag);
		else
			buffer_fadd(buf,"<%s>%lf</%s>",tag,obj->double_value,tag);


	} else if (obj->is_array) {
		if(!obj->classname) {
			if(!fm_class)
        	       		buffer_add(buf,"<array>");
			else
               			buffer_fadd(buf,"<%s>",tag);
		}

	       	for( i = 0; i!= obj->size; i++ ) {
			_rest_xml_output(buf, obj->get_index(obj,i), obj->classname, i);
		}

		if(!obj->classname) {
			if(!fm_class)
        	       		buffer_add(buf,"</array>");
			else
               			buffer_fadd(buf,"</%s>",tag);
		}

        } else if (obj->is_hash) {

       		if(!obj->classname) {
			if(!fm_class)
        	       		buffer_add(buf,"<hash>");
			else
               			buffer_fadd(buf,"<%s>",tag);
		}

                object_iterator* itr = new_iterator(obj);
                object_node* tmp;
                while( (tmp = itr->next(itr)) ) {
			if (obj->classname) {
				buffer_fadd(buf,"<%s>",tmp->key);
			} else {
				buffer_add(buf,"<pair>");
				buffer_fadd(buf,"<key>%s</key><value>",tmp->key);
			}

                        _rest_xml_output(buf, tmp->item, NULL,0);

			if (obj->classname) {
				buffer_fadd(buf,"</%s>",tmp->key);
			} else {
				buffer_add(buf,"</value></pair>");
			}
                }
                free_iterator(itr);
		if(!obj->classname) {
			if(!fm_class)
        	       		buffer_add(buf,"</hash>");
			else
               			buffer_fadd(buf,"</%s>",tag);
		}

	}

        if(obj->classname)
                buffer_fadd(buf,"</Object></%s>",tag);
}

char * _lookup_fm_field(char * class, int pos) {

C

print SOURCE "	if (class == NULL) return NULL;";

for my $object (keys %$map) {

	my $short_name				= $map->{$object}->{hint};

	print SOURCE <<"	C";

	else if (!strcmp(class, "$short_name")) {
		switch (pos) {
	C

	for my $field (keys %{$map->{$object}->{fields}}) {
		my $position = $map->{$object}->{fields}->{$field}->{position};

		print SOURCE <<"		C";
			case $position:
				return strdup("$field");
				break;
		C
	}
	print SOURCE "		}\n";
	print SOURCE "	}\n";
}
print SOURCE '	return strdup("datum");'."\n";
print SOURCE "}\n";

close HEADER;
close SOURCE;

warn  "done\n";

