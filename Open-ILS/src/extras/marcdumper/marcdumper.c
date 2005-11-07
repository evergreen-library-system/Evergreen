/*
* Copyright (C) 1995-2005, Index Data ApS
* See the file LICENSE for details.
*
* $Id$
*/

#if HAVE_CONFIG_H
#include <config.h>
#endif

#include <libxml/parser.h>
#include <libxml/tree.h>

#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#if HAVE_LOCALE_H
#include <locale.h>
#endif
#if HAVE_LANGINFO_H
#include <langinfo.h>
#endif

#include <yaz/marcdisp.h>
#include <yaz/yaz-util.h>
#include <yaz/xmalloc.h>
#include <yaz/options.h>

#ifndef SEEK_SET
#define SEEK_SET 0
#endif
#ifndef SEEK_END
#define SEEK_END 2
#endif

#include <fcntl.h>

char* clean_marc_xpath	= "//*[@tag=\"999\"]";
char* holdings_xpath		= "/*/*[(local-name()='datafield' and "
									"(@tag!='035' and @tag!='999')) or local-name()!='datafield']";

void prune_doc( xmlDocPtr doc, char* xpath );
char* _xml_to_string( xmlDocPtr doc );

static void usage(const char *prog) {
	fprintf (stderr, "Usage: %s -r [xpath] -c [cfile] [-f from] [-t to] [-x] [-O] [-X] [-I] [-v] file...\n", prog);
} 

int main (int argc, char **argv) {
	int counter = 0;

	int r;
	int libxml_dom_test = 0;
	int print_offset = 0;
	char *arg;
	int verbose = 0;
	FILE *inf;
	char buf[100001];
	char *prog = *argv;
	int no = 0;
	int xml = 0;
	FILE *cfile = 0;
	char *from = 0, *to = 0;
	int num = 1;
	
	#if HAVE_LOCALE_H
	setlocale(LC_CTYPE, "");
	#endif
	#if HAVE_LANGINFO_H
	#ifdef CODESET
	to = nl_langinfo(CODESET);
	#endif
	#endif
	
	char* prune = NULL;
	while ((r = options("pvcr:xOeXIf:t:2", argv, argc, &arg)) != -2) {
			
		int count;
		no++;

		switch (r) {
			case 'r':
				prune = arg;
				xmlKeepBlanksDefault(0);
				break;
			case 'f':
				from = arg;
				break;
			case 't':
				to = arg;
				break;
			case 'c':
				if (cfile)
				fclose (cfile);
				cfile = fopen (arg, "w");
			break;
				case 'x':
				xml = YAZ_MARC_SIMPLEXML;
				break;
			case 'O':
				xml = YAZ_MARC_OAIMARC;
				break;
			//case 'e': /* not supported on older versions of yaz */
			//	xml = YAZ_MARC_XCHANGE;
			//	break;
			case 'X':
				xml = YAZ_MARC_MARCXML;
				break;
			case 'I':
				xml = YAZ_MARC_ISO2709;
				break;
			case 'p':
				print_offset = 1;
				break;
			case '2':
				libxml_dom_test = 1;
				break;
			case 0:

				inf = fopen (arg, "rb");
				count = 0;
				if (!inf) {
					fprintf (stderr, "%s: cannot open %s:%s\n",
					prog, arg, strerror (errno));
					exit(1);
				}
				if (cfile)
					fprintf (cfile, "char *marc_records[] = {\n");

				if (1) {
					yaz_marc_t mt = yaz_marc_create();
					yaz_iconv_t cd = 0;
			
					if (from && to) {
						cd = yaz_iconv_open(to, from);
						if (!cd) {
							fprintf(stderr, "conversion from %s to %s " "unsupported\n", from, to);
							exit(2);
						}
						yaz_marc_iconv(mt, cd);
					}
					yaz_marc_xml(mt, xml);
					yaz_marc_debug(mt, verbose);

					while (1) {
						int len;
						char *result;
						int rlen;
						
						r = fread (buf, 1, 5, inf);

						if (r < 5) {
							if (r && print_offset)
								printf ("Extra %d bytes", r);
							break;
						}

						if (print_offset) {
							long off = ftell(inf);
							printf ("Record %d offset %ld\n", num, (long) off);
						}

						len = atoi_n(buf, 5);

						if (len < 25 || len > 100000) break;

						len = len - 5;
						r = fread (buf + 5, 1, len, inf);
		
						if (r < len) break;

						r = yaz_marc_decode_buf (mt, buf, -1, &result, &rlen);
		
						if (r <= 0) break;
		


						counter++;
						if(!prune) {

							fwrite (result, rlen, 1, stdout);

						} else {


							xmlDocPtr doc = xmlParseMemory(result, rlen);

							if (doc) {
								prune_doc( doc, prune );
								char* marc = _xml_to_string(doc);
								fprintf(stdout, "%s", marc);

								free(marc);
								xmlFreeDoc(doc);

							} else {

								fprintf(stderr, "xmLParseMemory failed for record %d\n", counter);
							}

						}


						if (cfile) {
				
							char *p = buf;
							int i;
							if (count)
								fprintf (cfile, ",");
							fprintf (cfile, "\n");
							for (i = 0; i < r; i++) {
								if ((i & 15) == 0)
									fprintf (cfile, "  \"");
								fprintf (cfile, "\\x%02X", p[i] & 255);
					
								if (i < r - 1 && (i & 15) == 15)
									fprintf (cfile, "\"\n");
					
							}
							fprintf (cfile, "\"\n");
						}
						num++;
					}
				
					count++;
		
					if (cd)
						yaz_iconv_close(cd);
					yaz_marc_destroy(mt);
				}


				if (cfile)
					fprintf (cfile, "};\n");
				fclose(inf);
				break;
			case 'v':
				verbose++;
				break;
			default:
				usage(prog);
				exit (1);
		}
	}

	if (cfile)
		fclose (cfile);
	if (!no) {
		usage(prog);
		exit (1);
	}

	fprintf(stderr, "\nProcessed %d Records\n", counter );
	exit (0);
}


void prune_doc( xmlDocPtr doc, char* xpath ) {

	xmlXPathContextPtr xpathctx;
	xmlXPathObjectPtr object;

	xpathctx = xmlXPathNewContext(doc);
	if(xpathctx == NULL) {
		fprintf(stderr, "XPATH FAILED");
		return;
	}

	object = xmlXPathEvalExpression( BAD_CAST xpath, xpathctx);
	if(object == NULL) return;

	int i;
	int size = object->nodesetval->nodeNr;
	for(i=0; i!= size; i++ ) {
		xmlNodePtr cur_node = (xmlNodePtr) object->nodesetval->nodeTab[i];
		xmlUnlinkNode( cur_node );
		xmlFreeNode( cur_node );
		object->nodesetval->nodeTab[i] = NULL;
	}

	xmlXPathFreeObject(object);
   xmlXPathFreeContext(xpathctx); 	

	/* remove all comments and PI nodes */
	xmlNodePtr cur = doc->children;
	while(cur) {
		if( cur->type == XML_COMMENT_NODE || cur->type == XML_PI_NODE ) {
			xmlUnlinkNode( cur );
			xmlFreeNode( cur );
		}
		cur = cur->next;
	}


}

char* _xml_to_string( xmlDocPtr doc ) {
	
	int			bufsize;
	xmlChar*		xmlbuf;
	xmlDocDumpFormatMemory( doc, &xmlbuf, &bufsize, 0 );

	char* xml = strdup(xmlbuf);
	xmlFree(xmlbuf);

	/*** remove the XML declaration */
	int len = strlen(xml);
	char tmp[len];
	memset( tmp, 0, len );
	int i;
	int found_at = 0;
						
	/* when we reach the first >, take everything after it */
	for( i = 0; i!= len; i++ ) {
		if( xml[i] == 62) { /* ascii > */
	
			/* found_at holds the starting index of the rest of the doc*/
			found_at = i + 1; 
			break;
		}
	}

	if( found_at ) {

		/* move the shortened doc into the tmp buffer */
		strncpy( tmp, xml + found_at, len - found_at );
		/* move the tmp buffer back into the allocated space */
		memset( xml, 0, len );
		strcpy( xml, tmp );
	}

	int l = strlen(xml)-1;
	if( xml[l] == 10 || xml[l] == 13 )
		xml[l] = '\0';

	return xml;

}
