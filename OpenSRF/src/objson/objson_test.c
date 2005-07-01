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

	/* sample JSON string with some encoded UTF8 */
	char* jsons = "/*--S mvr--*/[null,null,null,\"Griswold del Castillo, Richard\",[],null,\"1405676\",null,null,\"1558853243 (alk. paper) :\",\"c2002\",\"Pin\\u0303ata Books\",null,[],[[\"Chavez, Cesar 1927-\",\"Juvenile literature\"],[\"Labor leaders\",\"United States\",\"Biography\",\"Juvenile literature\"],[\"Mexican Americans\",\"Biography\",\"Juvenile literature\"],[\"Agricultural laborers\",\"Labor unions\",\"United States\",\"History\",\"Juvenile literature\"],[\"United Farm Workers\",\"History\",\"Juvenile literature\"],[\"Chavez, Cesar 1927-\"],[\"Labor leaders\"],[\"Mexican Americans\",\"Biography\"],[\"United Farm Workers.\"],[\"Spanish language materials\",\"Bilingual\"],[\"Chavez, Cesar 1927-\",\"Literatura juvenil\"],[\"Li\\u0301deres obreros\",\"Estados Unidos\",\"Biografi\\u0301a\",\"Literatura juvenil\"],[\"Mexicano-americanos\",\"Biografi\\u0301a\",\"Literatura juvenil\"],[\"Sindicatos\",\"Trabajadores agri\\u0301colas\",\"Estados Unidos\",\"Historia\",\"Literatura juvenil\"],[\"Unio\\u0301n de Trabajadores Agri\\u0301colas\",\"Historia\",\"Literatura juvenil\"]],\"ocm48083852 \",\"Ce\\u0301sar Cha\\u0301vez : the struggle for justice = Ce\\u0301sar Cha\\u0301vez : la lucha por la justicia\",[\"text\"], { \"hi\":\"you\"} ]/*--E mvr--*/";


	printf("\nOriginal JSON\n%s\n", jsons); 

	/* parse the JSON string */
	object* yuk = json_parse_string(jsons); 

	/* grab the class name from the object */
	printf("\nParsed object with class %s\n", yuk->classname );

	/* turn the resulting object back into JSON */
	char* ccc = yuk->to_json(yuk); 
	
	/* extract a sub-object from the object and print its data*/
	object* o = yuk->get_index(yuk, 11);
	printf("\nRandom unicode string => %s\n", o->string_data);

	/* parse the new JSON string to build yet another object */
	object* yuk2 = json_parse_string(ccc);

	/* turn that one back into JSON and print*/
	char* cccc = yuk2->to_json(yuk2);
	printf("\nFinal JSON: \n%s\n", cccc);

	char* string2 = strdup(jsons);

	int x = 0;
	int count = 10000;
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
	object* big = json_parse_string(buf);
	object* k = big->get_key(big,"web-app");
	object* k2 = k->get_key(k,"servlet");
	object* k3 = k2->get_index(k2, 0);
	object* k4 = k3->get_key(k3,"servlet-class");

	printf("\nValue for object with key 'servlet-class' in the JSON file => %s\n", k4->get_string(k4));

	return 0;
}


