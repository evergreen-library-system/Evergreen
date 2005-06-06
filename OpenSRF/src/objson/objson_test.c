#include <stdio.h>
#include "utils.h"
#include <fcntl.h>
#include "object.h"
#include "json_parser.h"

#include <wchar.h>
#include <locale.h>


/* ---------------------------------------------------------------------- */
/* See object.h for function info */
/* ---------------------------------------------------------------------- */
int main() {

	char* jsons = "/*--S mvr--*/[null,null,null,\"Griswold del Castillo, Richard\",[],null,\"1405676\",null,null,\"1558853243 (alk. paper) :\",\"c2002\",\"Pin\\u0303ata Books\",null,[],[[\"Chavez, Cesar 1927-\",\"Juvenile literature\"],[\"Labor leaders\",\"United States\",\"Biography\",\"Juvenile literature\"],[\"Mexican Americans\",\"Biography\",\"Juvenile literature\"],[\"Agricultural laborers\",\"Labor unions\",\"United States\",\"History\",\"Juvenile literature\"],[\"United Farm Workers\",\"History\",\"Juvenile literature\"],[\"Chavez, Cesar 1927-\"],[\"Labor leaders\"],[\"Mexican Americans\",\"Biography\"],[\"United Farm Workers.\"],[\"Spanish language materials\",\"Bilingual\"],[\"Chavez, Cesar 1927-\",\"Literatura juvenil\"],[\"Li\\u0301deres obreros\",\"Estados Unidos\",\"Biografi\\u0301a\",\"Literatura juvenil\"],[\"Mexicano-americanos\",\"Biografi\\u0301a\",\"Literatura juvenil\"],[\"Sindicatos\",\"Trabajadores agri\\u0301colas\",\"Estados Unidos\",\"Historia\",\"Literatura juvenil\"],[\"Unio\\u0301n de Trabajadores Agri\\u0301colas\",\"Historia\",\"Literatura juvenil\"]],\"ocm48083852 \",\"Ce\\u0301sar Cha\\u0301vez : the struggle for justice = Ce\\u0301sar Cha\\u0301vez : la lucha por la justicia\",[\"text\"], { \"hi\":\"you\"} ]/*--E mvr--*/";


	//char* jsons = buffer_data(buffer);
	printf("\nOriginal JSON\n%s\n", jsons); 

	object* yuk = json_parse_string(jsons); 
	char* ccc = yuk->to_json(yuk); 
	
	object* o = yuk->get_index(yuk, 11);
	printf("\nRandom unicode string => %s\n", o->string_data);

	object* yuk2 = json_parse_string(ccc);
	char* cccc = yuk2->to_json(yuk2);

	printf("\nFinal JSON: \n%s\n", cccc);

	int x = 0;
	printf("\nParsing 10,000 round trips at %f...\n", get_timestamp_millis());

	char* string2 = strdup(jsons);
	while(x++ < 10000) {

		object* o = json_parse_string(string2); 
		free(string2);
		string2 = o->to_json(o);
		free_object(o);

		if(!(x%1000))
			fprintf(stderr, "Round trip at %d\n", x);
	}

	printf("\nAfter Loop: %f\n", get_timestamp_millis());


	free(string2);
	free(ccc); 
	free(cccc); 
	free_object(yuk); 
	free_object(yuk2); 
	//buffer_free(buffer);

	return 0;

}


