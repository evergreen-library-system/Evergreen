/*
Copyright (C) 2005  Georgia Public Library Service 
Bill Erickson <highfalutin@gmail.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

//#include "utils.h"
#include "object.h"
#include "json_parser.h"

#include <stdio.h>
#include <fcntl.h>

/* ---------------------------------------------------------------------- */
/* See object.h for function info */
/* ---------------------------------------------------------------------- */
int main() {



	object* o;


	printf("------------------------------------------------------------------\n");
	o = json_parse_string("[,,{\"key\":,\"key1\":\"a\"}]");
	char* h = o->to_json(o);
	printf("\nParsed number: %s\n", h);
	free_object(o);


	/* number, double, and 'null' parsing... */
	printf("------------------------------------------------------------------\n");
	 o = json_parse_string("1");
	printf("\nParsed number: %ld\n", o->num_value);
	free_object(o);


	printf("------------------------------------------------------------------\n");
	o = json_parse_string("1.1");
	printf("\nDouble number: %lf\n", o->double_value);
	free_object(o);

	printf("------------------------------------------------------------------\n");
	o = json_parse_string("nUlL");
	char* s = o->to_json(o);
	free_object(o);

	printf("\nJSON Null: %s\n", s);
	free(s);

	printf("------------------------------------------------------------------\n");
	o = json_parse_string("[1, .5, null]");
	s  = o->to_json(o);
	printf("\nJSON MIX: %s\n", s );
	free(s);
	free_object(o);

	printf("------------------------------------------------------------------\n");
	/* simulate an error.. */
	printf("\nShould print error msg: \n");
	o = json_parse_string("[1, .5. null]");
	if( o == NULL ) printf("\n"); 

	printf("------------------------------------------------------------------\n");
	o = json_parse_string("[ Null, trUe, falSE, 1, 12.9, \"true\" ]");
	s = o->to_json(o);
	printf("More JSON: %s\n", s);
	free(s);
	free_object(o);

	printf("------------------------------------------------------------------\n");
	o = json_parse_string("[ Null, trUe, falSE, 1, 12.9, \"true\", "
			"{\"key\":[0,0.0,1],\"key2\":null},NULL, { }, [] ]");
	s = o->to_json(o);
	printf("More JSON: %s\n", s);
	free(s);
	free_object(o);


	printf("------------------------------------------------------------------\n");
	o = json_parse_string("{ Null: trUe }");



	printf("------------------------------------------------------------------\n");
	o = json_parse_string("\"Pin\\u0303ata\"");
	s = o->to_json(o);
	printf("UNICODE:: %s\n", o->string_data);
	printf("Back to JSON: %s\n", s);
	free_object(o);
	free(s);


	/* sample JSON string with some encoded UTF8 */
	char* jsons = "/*--S mvr--*/[null,null,null,\"Griswold del Castillo, Richard\",[],null,\"1405676\",null,null,\"1558853243 (alk. paper) :\",\"c2002\",\"Pin\\u0303ata Books\",null,[],[[\"Chavez, Cesar 1927-\",\"Juvenile literature\"],[\"Labor leaders\",\"United States\",\"Biography\",\"Juvenile literature\"],[\"Mexican Americans\",\"Biography\",\"Juvenile literature\"],[\"Agricultural laborers\",\"Labor unions\",\"United States\",\"History\",\"Juvenile literature\"],[\"United Farm Workers\",\"History\",\"Juvenile literature\"],[\"Chavez, Cesar 1927-\"],[\"Labor leaders\"],[\"Mexican Americans\",\"Biography\"],[\"United Farm Workers.\"],[\"Spanish language materials\",\"Bilingual\"],[\"Chavez, Cesar 1927-\",\"Literatura juvenil\"],[\"Li\\u0301deres obreros\",\"Estados Unidos\",\"Biografi\\u0301a\",\"Literatura juvenil\"],[\"Mexicano-americanos\",\"Biografi\\u0301a\",\"Literatura juvenil\"],[\"Sindicatos\",\"Trabajadores agri\\u0301colas\",\"Estados Unidos\",\"Historia\",\"Literatura juvenil\"],[\"Unio\\u0301n de Trabajadores Agri\\u0301colas\",\"Historia\",\"Literatura juvenil\"]],\"ocm48083852 \",\"Ce\\u0301sar Cha\\u0301vez : the struggle for justice = Ce\\u0301sar Cha\\u0301vez : la lucha por la justicia\",[\"text\"], { \"hi\":\"you\"} ]/*--E mvr--*/";


	printf("------------------------------------------------------------------\n");
	printf("\nOriginal JSON\n%s\n", jsons); 

	/* parse the JSON string */
	object* yuk = json_parse_string(jsons); 

	/* grab the class name from the object */
	printf("------------------------------------------------------------------\n");
	printf("\nParsed object with class %s\n", yuk->classname );

	/* turn the resulting object back into JSON */
	char* ccc = yuk->to_json(yuk); 
	
	/* extract a sub-object from the object and print its data*/
	o = yuk->get_index(yuk, 11);
	printf("\nRandom unicode string => %s\n", o->string_data);

	/* parse the new JSON string to build yet another object */
	object* yuk2 = json_parse_string(ccc);

	printf("------------------------------------------------------------------\n");
	/* turn that one back into JSON and print*/
	char* cccc = yuk2->to_json(yuk2);
	printf("\nFinal JSON: \n%s\n", cccc);

	char* string2 = strdup(jsons);

	printf("------------------------------------------------------------------\n");
	int x = 0;
	int count = 3000;
	printf("\nParsing %d round trips at %f...\n", count, get_timestamp_millis());

	/* parse and stringify many times in a loop to check speed */
	while(x++ < count) {

		object* o = json_parse_string(string2); 
		free(string2);
		string2 = o->to_json(o);
		free_object(o);

		if(!(x % 500))
			fprintf(stderr, "Round trip at %d\n", x);
	}

	printf("After Loop: %f\n", get_timestamp_millis());


	/* to_json() generates a string that must be freed by the caller */
	free(string2);
	free(ccc); 
	free(cccc); 

	/* only free the top level objects.  objects that are 'children'
		of other objects should not be freed */
	free_object(yuk); 
	free_object(yuk2); 



	/* ------------------------------------------------------------------------ */

	/* parse a big JSON file */
	FILE* F = fopen("test.json", "r");
	if(!F) {
		perror("unable to open test.json for testing");
		exit(99);
	}

	char buf[10240];
	char smallbuf[512];
	bzero(buf, 10240);
	bzero(smallbuf, 512);

	while(fgets(smallbuf, 512, F)) 
		strcat(buf, smallbuf);

	/* dig our way into the JSON object we parsed, see test.json to get
	   an idea of the object structure */
	printf("------------------------------------------------------------------\n");
	object* big = json_parse_string(buf);
	object* k = big->get_key(big,"web-app");
	object* k2 = k->get_key(k,"servlet");
	object* k3 = k2->get_index(k2, 0);
	object* k4 = k3->get_key(k3,"servlet-class");

	printf("\nValue for object with key 'servlet-class' in the JSON file => %s\n", k4->get_string(k4));


	

	return 0;
}


