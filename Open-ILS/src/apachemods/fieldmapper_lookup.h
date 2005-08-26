
#include <string.h>
#include <stdio.h>

/* the JSON parser, so we can read the response we're XMLizing */
#include "objson/object.h"
#include "objson/json_parser.h"
#include "utils.h"

int isFieldmapper(char*);
int fm_ntop(char*,char*);
char* fm_pton(char*,int);

