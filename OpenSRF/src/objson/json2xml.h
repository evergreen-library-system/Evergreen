
#include <string.h>
#include <stdio.h>

/* the JSON parser, so we can read the response we're XMLizing */
#include "object.h"
#include "json_parser.h"
#include "utils.h"

char* jsonObjectToXML(jsonObject*);

