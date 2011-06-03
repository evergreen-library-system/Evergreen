/*
* Function: permissions_list_to_docbook2() 
 * Copyright (C) 2011  Robert Soulliere <robert.soulliere@mohawkcollege.ca>
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * This function can be used for generating a DocBook appendix in XML format to be included in the Evergreen DocBook documentation. 
 * It takes the code and descrtiption values from permission.perm_list and formats it into XML. Some cleanup is required to remove added lines in the beginning and end of the file. 
 * To run this script simple use the following commands from psql:
 * \g permissions.xml
 * SELECT * FROM permissions_list_to_docbook2();
*/

CREATE OR REPLACE FUNCTION permissions_list_to_docbook2()
  RETURNS text AS
$BODY$
DECLARE
    r permission.perm_list;
  --  r permission.perm_list;
    strXML xml;
  strHead text;
  strFoot text;
  xmlCode xml;
  xmlTerm xml;
  xmlTermEnd xml;
  --  description permission.perm_list.description;
BEGIN
	FOR r.code, r.description IN SELECT code, description FROM permission.perm_list AS pl WHERE id > 0 ORDER BY code
			LOOP   
				XMLTerm = XMLCONCAT(XMLTerm, '
			',	
					XMLELEMENT (name formalpara,
						XMLCONCAT('

				',
							XMLELEMENT(
								name title,
								r.code), '
				',   
							XMLELEMENT(
								name para, 
								r.description), '
			'
			
						)
					)
				);
				
			--	XMLTerm = XMLCONCAT(XMLTerm,  XMLELEMENT (name listitem, r.description), '
			--');
			END LOOP;

	strXML = XMLELEMENT (
		name appendix, 
		XMLATTRIBUTES(
			'http://docbook.org/ns/docbook' AS "xmlns",
			'http://www.w3.org/2001/XInclude' AS "xmlns:xi",
			'http://www.w3.org/1999/xlink' AS "xmlns:xl",
			'5.0' as version, 
			'permissions_appendix' AS "xml:id"
		),
		XMLCONCAT(
			' 
	',
			XMLELEMENT (
				name info, 
				XMLELEMENT (name title, 'Permissions List')
			), '
	', 
			XMLELEMENT (
				name section,
				XMLATTRIBUTES(
				  'permission_descriptions' AS "xml:id"
				),
				XMLCONCAT (
					' 
		',
					XMLELEMENT (name title, 'Permission Descriptions'), 
					' ',
					XMLCONCAT (' 
			', 			XMLTerm, ' 
		')
							
				), '
	'
					
			)
		), '
'
	);					
 RETURN strXML;
END
$BODY$
  LANGUAGE 'plpgsql' VOLATILE
  COST 100;



