#!/usr/bin/env python3
import argparse
import os, re
from collections import defaultdict
from bs4 import BeautifulSoup, Tag

def escape_single_quotes(s):
    # This doesn't protect against SQL-injection and we don't want to connect to a database to use parameterized queries.
    # But better than nothing.
    return s.replace("'", "''")

def clean_string(s):
    return s.strip() or None

def record_category_to_sql(record_category):
    """
    Define a mapping from record_category to the SQL condition
    """
    record_category_conditions = {
        'authority': "AND rec_type = 'AUT'",
        'biblio': "AND rec_type NOT IN ('AUT')"
    }
    if not record_category_conditions[record_category]:
        raise ValueError('Unhandled record category')
    return record_category_conditions[record_category];

def record_type_label_to_code(record_type_label):
    """
    Define a mapping from the HTML rec_type label to the MARC/EG code
    """
    record_types = {
        'All Materials' : "('COM', 'SCO', 'REC', 'MIX', 'MAP', 'VIS', 'BKS', 'SER')",
        'Books' : "('BKS')",
        'Computer Files' : "('COM')",
        'Music' : "('SCO')",
        'Maps' : "('MAP')",
        'Continuing Resources' : "('SER')",
        'Visual Materials' : "('VIS')",
        'Mixed Materials' : "('MIX')"
    }
    if not record_types[record_type_label]:
        raise ValueError('Unhandled record type label')
    return record_types[record_type_label]

def generate_sql_for_indicators(tag, soup, record_category = 'broken'):
    """
    Wrapper function for generating sql for subfield indicators from different types of LoC HTML files.
    """
    indicators_dl_div = soup.select_one('div.indicators')
    indicator_head = soup.select_one('div.indicatorhead')
    if indicators_dl_div and indicator_head:
        print(f"{tag}:Warning, indicators have multiple...indicators for the html encoding scheme")
        return []
    elif indicators_dl_div:
        return generate_sql_for_indicators_from_dl_templated_html(tag, indicators_dl_div, record_category)
    elif indicator_head:
        return generate_sql_for_indicators_from_div_templated_html(tag, indicator_head, record_category)
    elif int(re.sub(r"\D",'0',tag)) > 10: # datafield that has indicators
        print(f"{tag}:Warning, indicators not encoded with class indicators nor indicatorhead")
        return []
    # else controlfield, which don't have indicators
    return []

def generate_sql_for_indicators_from_div_templated_html(tag, indicator_head, record_category = 'broken'):
    """
    Function for generating sql for subfield indicators from a specific type of LoC HTML file (the older ones).
    """
    sql_statements = []
    indicator_values = indicator_head.find_next_siblings('div', class_='indicatorvalue')
    for i, ind_val in enumerate(indicator_values):
        indicator_position = i + 1
        indicator_identifier = f'marc21_{record_category}_{tag}_ind_{indicator_position}'
        label = next(ind_val.stripped_strings)
        ind_desc_divs = ind_val.find_all('div', class_='indicatorvalue')
        descriptions = []
        for div in ind_desc_divs:
            descriptions.append(div.text.strip())

        description = '' # escape_single_quotes( ' '.join(descriptions).replace('\n', ' ').replace('  ', ' ') )
        formatted_description = f"\n\n{description}\n\n"
        clean_description = clean_string(formatted_description)
        escaped_description = escape_single_quotes(clean_description) if clean_description else 'NULL'

        # Construct the SQL command
        sql = f"""INSERT INTO config.record_attr_definition (name, label, description) VALUES (
            $ident${escape_single_quotes(indicator_identifier)}$ident$,
            BTRIM($label${escape_single_quotes(label)}\n\n$label$),
            {f"E'{escaped_description}'" if clean_description is not None else 'NULL'}
        ) ON CONFLICT (name) DO UPDATE SET
            label = EXCLUDED.label,
            description = EXCLUDED.description;

        """
        sql_statements.append(sql)
        sql_statements += generate_sql_for_indicator_values(indicator_identifier, descriptions, record_category)
    return sql_statements

def generate_sql_for_indicators_from_dl_templated_html(tag, indicators_dl_div, record_category = 'broken'):
    """
    Function for generating sql for subfield indicators from a specific type of LoC HTML file (the newer ones).
    """
    dl = indicators_dl_div.find('dl')
    if dl is None:
        print(f"{tag}:html file does not use dd for indicators")
        return []

    sql_statements = []
    dt_elements = dl.find_all('dt')

    for i, dt in enumerate(dt_elements):
        warnings = []
        indicator_position = i + 1
        indicator_identifier = f'marc21_{record_category}_{tag}_ind_{indicator_position}'
        label = escape_single_quotes( dt.get_text().strip() )
        description_texts = []
        for sibling in dt.find_next_siblings(['dt', 'dd']):
            if sibling.name == 'dt':
                break
            description_texts.append(sibling.get_text().strip())
        description = '' # escape_single_quotes( '\n'.join(description_texts) )
        if len(warnings) > 0:
            print('\n'.join(warnings))
        sql = f"INSERT INTO config.record_attr_definition (name, label, description) VALUES ('{indicator_identifier}', BTRIM($label$\n\n{label}\n\n$label$), BTRIM($desc$\n\n{description}\n\n$desc$)) ON CONFLICT (name) DO UPDATE SET label = EXCLUDED.label, description = EXCLUDED.description;" + ' -- '.join(warnings) + "\n\n"
        sql_statements.append(sql)
        sql_statements += generate_sql_for_indicator_values(indicator_identifier, description_texts, record_category)
    return sql_statements

def generate_sql_for_indicator_values(ctype, unparsed_value_strings, record_category = 'broken'):
    """
    Function for generating sql for specific indicator values.
    """
    sql_statements = []
    for value_string in unparsed_value_strings:
        unparsed_value = escape_single_quotes( value_string )
        # Extract code and value
        raw_code, value = unparsed_value.split(' - ', 1)
        codes = parse_range(raw_code.strip())  # Remove whitespace and parse range if we have one
        value_description = '' # Not set in this context
        for code in codes:  # Generate SQL for each code
            # Generate SQL UPSERT statement for config.coded_value_map
            upsert_sql = f"SELECT evergreen.simple_insert_update_coded_value_map('{ctype}', '{code}', '{value}', '{value_description}');"
            sql_statements.append(upsert_sql)

    return sql_statements

def generate_sql_for_subfields(tag, soup, record_category = 'broken'):
    """
    Wrapper function for generating sql for subfields from different types of LoC HTML files.
    """
    subfields_dl_div = soup.select_one('div.subfields')
    subfield_head = soup.select_one('div.subfieldhead')
    if subfields_dl_div and subfield_head:
        print(f"{tag}:Warning, subfields seem to have multiple html encoding schemes")
        return []
    elif subfields_dl_div:
        print(f"{tag}:debug, calling generate_sql_for_subfields_from_dl_templated_html")
        return generate_sql_for_subfields_from_dl_templated_html(tag, subfields_dl_div, record_category)
    elif subfield_head:
        print(f"{tag}:debug, calling generate_sql_for_subfields_from_div_templated_html")
        return generate_sql_for_subfields_from_div_templated_html(tag, subfield_head, record_category)
    elif int(re.sub(r"\D",'0',tag)) > 10: # datafield that has subfields
        print(f"{tag}:Warning, subfields not encoded with class subfields nor subfieldhead")
        return []
    # else controlfield, which don't have subfields
    return []

def generate_sql_for_subfields_from_dl_templated_html(tag, subfields_dl_div, record_category = 'broken'):
    """
    Function for generating sql for subfields from a specific type of LoC HTML file (the newer ones).
    """
    dl = subfields_dl_div.find('dl')
    #print(f"dl:\n{dl}\n")
    if dl is None:
        print(f"{tag}: html file does not use dd for subfields")
        return []

    sql_statements = []
    dt_elements = dl.find_all('dt')
    #print(f"dt_elements:\n{dt_elements}\n")
    subfield_descriptions = {}

    for dt in dt_elements:
        #print(f"dt:\n{dt}\n")
        warnings = []
        # Extract code and title from <dt>
        raw_code, title = dt.text.split(' - ', 1)
        codes = parse_range(raw_code.replace('$', '').strip())  # Remove $ and whitespace and parse range if we have one
        # Check for repeatable flag
        is_repeatable = 't' if '(R)' in title else 'f'
        description_texts = [dt.get_text()]
        for sibling in dt.find_next_siblings(['dt', 'dd']):
            if sibling.name == 'dt':
                break
            description_texts.append(sibling.get_text().strip())
        description = escape_single_quotes( '\n'.join(description_texts) )
        if len(warnings) > 0:
            print('\n'.join(warnings))
        for code in codes:  # Generate SQL for each code
            print(f"tag:\n{tag}\ncode:\n{code}\ndescription:\n{description}\nrepeatable:\n{is_repeatable}\n\n")
            sql = f"""INSERT INTO config.marc_subfield (marc_record_type, marc_format, tag, code, description, repeatable, hidden, mandatory)
              VALUES ('{record_category}', 1, '{tag}', '{code}', '{description}','{is_repeatable}','f','f')
              ON CONFLICT (marc_record_type, marc_format, tag, code) WHERE owner IS NULL
              DO UPDATE SET description = EXCLUDED.description, repeatable = EXCLUDED.repeatable;""" + ' -- '.join(warnings) + "\n\n"
            sql_statements.append(sql)

    return sql_statements

def generate_sql_for_subfields_from_div_templated_html(tag, subfield_head, record_category = 'broken'):
    """
    Function for generating sql for subfields from a specific type of LoC HTML file (the older ones).
    """
    subfield_values = subfield_head.find_next_siblings('div', class_='subfieldvalue')
    print(f"subfield_values:\n{subfield_values}\n")
    for subfield_val in subfield_values:
        warnings = []
        print(f"subfield_val:\n{subfield_val}\n")
        label = next(subfield_val.stripped_strings)
        print(f"label:\n{label}\n")
        # Extract code and title from immediate text content of first div
        raw_code, title = label.split(' - ', 1)
        codes = parse_range(raw_code.replace('$', '').strip())  # Remove $ and whitespace and parse range if we have one
        subfield_desc_divs = subfield_val.find_all('div', class_='description')
        # Check for repeatable flag
        is_repeatable = 't' if '(R)' in title else 'f'
        descriptions = [ label ]
        for div in subfield_desc_divs:
            descriptions.append(div.text.strip())

        description = escape_single_quotes( ' '.join(descriptions).replace('\n', ' ').replace('  ', ' ') )
        description = re.sub(r'\s+', ' ', description)  # Replace consecutive whitespace with a single space
        if len(warnings) > 0:
            print('\n'.join(warnings))
        for code in codes:  # Generate SQL for each code
            print(f"tag:\n{tag}\ncode:\n{code}\ndescription:\n{description}\nrepeatable:\n{is_repeatable}\n\n")
            sql = f"""INSERT INTO config.marc_subfield (marc_record_type, marc_format, tag, code, description, repeatable, hidden, mandatory)
              VALUES ('{record_category}', 1, '{tag}', '{code}', '{description}','{is_repeatable}','f','f')
              ON CONFLICT (marc_record_type, marc_format, tag, code) WHERE owner IS NULL
              DO UPDATE SET description = EXCLUDED.description, repeatable = EXCLUDED.repeatable;""" + ' -- '.join(warnings) + "\n\n"
            sql_statements.append(sql)
    return sql_statements

def clean_start_pos(start_pos_str):
    """
    Function to extract the start position from a string representing a range, handling various variances.
    """
    # If it's a range like "00-04", take the first part
    if '-' in start_pos_str:
        start_pos_str = start_pos_str.split('-')[0]
    
    # Remove leading zeros
    start_pos_str = start_pos_str.lstrip('0')
    
    # Convert to integer, handle empty string case
    return int(start_pos_str) if start_pos_str else 0

def generate_sql_for_006_008(tag, soup, record_category = 'broken'):
    """
    Function for generating sql for tag 006 or 008 from its corresponding LoC HTML file.
    """

    update_statements = []
    upsert_statements = []

    # Find all divs with class 'characterposition'
    character_positions = soup.find_all('div', class_='characterposition')

    for char_pos in character_positions:
        # Extract the fixed field name and range
        field_info_strong = char_pos.find('strong')
        if field_info_strong:
            field_info = field_info_strong.text  # e.g., "00 - Form of material"

        # Extract the description, if present
        description_div = char_pos.find('div', class_='description')
        description = escape_single_quotes( description_div.text ) if description_div else ''

        # Extracting byte range or position
        byte_text = re.search(r'(\d+(\-\d+)?)', field_info_strong.text).group(0)
        print(f"byte_text:\n{byte_text}\n")
        if byte_text is None:
            continue
        start_pos = clean_start_pos(byte_text)

        rec_type_sql = record_category_to_sql(record_category)

        # Generate SQL UPDATE statement for config.record_attr_definition
        update_sql = f"""
        UPDATE config.record_attr_definition
        SET description = '{description}'
        WHERE fixed_field = (SELECT fixed_field FROM config.marc21_ff_pos_map WHERE tag = '{tag}' AND start_pos = {start_pos} {rec_type_sql} LIMIT 1);
        """
        update_statements.append(update_sql)

        # Extract charactervalues, if present
        char_values_divs = char_pos.find_all('div', class_='charactervalue')

        # Handling coded_value_map
        for char_value_div in char_values_divs:
            code = None
            label = None
            char_value_text = ''
            value_description = ''
            
            if char_value_div.contents and isinstance(char_value_div.contents[0], Tag) and char_value_div.contents[0].name == 'strong':
                # expecting <div class="charactervalue"><strong>code - label</strong><div class="description">description</div></div>
                char_value_text = char_value_div.contents[0].get_text()
            else:
                # expecting who knows what
                char_value_text = char_value_div.get_text()

            split_index = char_value_text.find(' - ')
            if split_index != -1:
                code = char_value_text[:split_index].strip()
                label = char_value_text[split_index + 3:].strip()
            else:
                # Handle cases where ' - ' is not found
                code = char_value_text.strip()
                label = ''

            if len(char_value_div.contents) > 1 and isinstance(char_value_div.contents[1], Tag) and char_value_div.contents[1].name == 'div':
                # expecting <div class="charactervalue"><strong>code - label</strong><div class="description">description</div></div>
                value_description = char_value_div.contents[1].get_text()
            else:
                # expecting label to have multiple lines, need to set label to the first line, and value_description to the remaining
                lines = char_value_text.split('\n')
                label = lines[0].strip()
                value_description = '\n'.join(lines[1:]).strip()

            print(f"code:\n{code}\n")
            print(f"label:\n{label}\n")
            print(f"description:\n{value_description}\n")

            if code is None:
                continue
            if label is None:
                continue
          
            tag = escape_single_quotes(tag)
            code = escape_single_quotes(code)
            label = escape_single_quotes(label)
            value_description = escape_single_quotes(value_description) 

            # Generate SQL UPSERT statement for config.coded_value_map
            upsert_sql = f"SELECT evergreen.insert_update_coded_value_map('{tag}', {start_pos}, '{code}', '{label}', '{value_description}', '{record_category}');"
            upsert_statements.append(upsert_sql)

    return update_statements + upsert_statements

def generate_sql_for_fixed_fields(tag, soup, record_category = 'broken'):
    """
    Function for generating sql for various fixed fields from an LoC HTML File. Tag 006 has its own function.
    """
    # Find all divs under characterPositions
    character_positions = soup.select('div.characterPositions > div')
    #print(f"character_positions:\n{character_positions}\n")
    
    update_statements = []
    upsert_statements = []

    record_type_code = None
    #if record_category == 'biblio' and tag == '008':
    #    tag_and_record_type = soup.find('strong')
    #    if tag_and_record_type:
    #        tag_and_record_type_match = re.match(r'(\d{3}) \((.+)\)', tag_and_record_type.text)
    #        if tag_and_record_type_match:
    #            record_type_label = tag_and_record_type_match.group(2)
    #            extracted_tag = tag_and_record_type_match.group(1)
    #            if extracted_tag != tag:
    #                raise ValueError('Unexpected tag found')
    #            record_type_code = record_type_label_to_code(record_type_label)

    for char_pos in character_positions:
        print(f"char_pos:\n{char_pos}\n")
        strong_tag = char_pos.find('strong')
        print(f"strong_tag:\n{strong_tag}\n")
        if strong_tag is None:
            continue
        first_p_tag = char_pos.find('p')
        description_paragraphs = []

        if first_p_tag is not None:
            description_paragraphs.append(first_p_tag.text)

            for sibling in first_p_tag.find_next_siblings():
                if sibling.name == 'p':
                    description_paragraphs.append(sibling.text)
                else:
                    break  # Stop collecting once we encounter a non-p tag

        description = ''
        if len(description_paragraphs) > 0:
            description = escape_single_quotes( '\n'.join(description_paragraphs) )
        print(f"description:\n{description}\n")
        
        # Extracting byte range or position
        byte_text = re.search(r'(\d+(\-\d+)?)', strong_tag.text).group(0)
        print(f"byte_text:\n{byte_text}\n")
        if byte_text is None:
            continue
        start_pos = clean_start_pos(byte_text)

        rec_type_sql = f"rec_type IN '{record_type_code}'" if record_type_code else record_category_to_sql(record_category)

        # Generate SQL UPDATE statement for config.record_attr_definition
        update_sql = f"""
        UPDATE config.record_attr_definition
        SET description = '{description}'
        WHERE fixed_field = (SELECT fixed_field FROM config.marc21_ff_pos_map WHERE tag = '{tag}' AND start_pos = {start_pos} {rec_type_sql} LIMIT 1);
        """
        update_statements.append(update_sql)
        
        # Handling coded_value_map
        for value_div in char_pos.select('div.value'):
            #print(f"value_div:\n{value_div}\n")
            value_label = value_div.find('span', {'class': 'valueLabel'})
            #print(f"value_label:\n{value_label}\n")
            if value_label is None:
                continue
            value_p = value_div.find('p')
            #print(f"value_p:\n{value_p}\n")
            
            # Extracting code and label
            code, label = value_label.text.split(' - ')
            print(f"code:\n{code}\n")
            print(f"label:\n{label}\n")
            if code is None:
                continue
            if label is None:
                continue
           
            value_description = ''
            if value_p is not None:
                # Extracting description
                value_description = value_p.text
            print(f"value_description:\n{value_description}\n")

            tag = escape_single_quotes(tag)
            code = escape_single_quotes(code)
            label = escape_single_quotes(label)
            value_description = escape_single_quotes(value_description) 

           # Generate SQL UPSERT statement for config.coded_value_map
            upsert_sql = f"SELECT evergreen.insert_update_coded_value_map('{tag}', {start_pos}, '{code}', '{label}', '{value_description}', '{record_category}');"
            upsert_statements.append(upsert_sql)

    return update_statements + upsert_statements

def write_out_file(filename, output):
    #print(f"{filename}: {output}")
    with open(filename, 'a') as out_file:
        out_file.write(output)

def parse_range(range_string):
    # This function checks if the input is a range and then enumerates it
    if '-' in range_string:
        start, end = range_string.split('-')
        if start.isdigit() and end.isdigit():
            return [str(i) for i in range(int(start), int(end) + 1)]
        elif len(start) == 1 and len(end) == 1:
            return [chr(i) for i in range(ord(start), ord(end) + 1)]
    return [range_string]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate SQL statements to update MARC 21 descriptions.')
    parser.add_argument('html_files', nargs='+', help='Paths to the HTML files containing the MARC 21 descriptions.')
    args = parser.parse_args()

    seen = defaultdict(bool)

    for html_file_path in args.html_files:
        sql_statements = []
        print(f"html_file_path = {html_file_path}")

        if os.path.basename(html_file_path)[:2] == 'bd':
            record_category = 'biblio'
        elif os.path.basename(html_file_path)[:2] == 'ad':
            record_category = 'authority'
        else:
            record_category = 'broken' # we can do serials another time

        tag = os.path.basename(html_file_path)[2:5]  # Extract MARC tag from filename
        sql_statements += [f'-- category: {record_category} tag: {tag} file: {html_file_path}']

        if seen[record_category + tag]:
            continue
        else:
            seen[record_category + tag] = True

        with open(html_file_path, 'r', encoding='utf-8') as html:
            soup = BeautifulSoup(html, 'html.parser')
            updated_on = soup.select_one('div.datename').get_text().strip()
            output_file = updated_on.replace(" ", "_") + '.sql'

            if len(soup.select('div.datename')) > 1:
                print(f"{html_file_path}:Warning, multiple datename divs")

            if tag == 'lea': # the leader
                sql_statements += generate_sql_for_fixed_fields('ldr', soup, record_category)
            elif tag == '006':
                # We're going to skip the 006; it's more complicated than what we have infrastructure for
                # sql_statements += generate_sql_for_006_008(tag, soup)
                print(f"Skipping {record_category} 006")
            elif tag == '008': # and record_category == 'authority':
                sql_statements += generate_sql_for_006_008(tag, soup, record_category)
            elif int(re.sub(r"\D",'0',tag)) <= 10: # controlfields / fixed fields
                sql_statements += generate_sql_for_fixed_fields(tag, soup, record_category)
            else: # datafields
                sql_statements += generate_sql_for_indicators(tag, soup, record_category)
                sql_statements += generate_sql_for_subfields(tag, soup, record_category)

        write_out_file(output_file, '\n'.join(sql_statements) + '\n')
        processed_record_category_tag_pairs = set()

    for html_file_path in args.html_files:
        tag = os.path.basename(html_file_path)[2:5]
        if os.path.basename(html_file_path)[:2] == 'bd':
            record_category = 'biblio'
        elif os.path.basename(html_file_path)[:2] == 'ad':
            record_category = 'authority'
        else:
            record_category = 'broken'

        # Skip tags equal to 'lea' or when tag as a number is less than or equal to 10
        if tag == 'lea' or int(re.sub(r'\D', '0', tag)) <= 10:
            continue

        processed_record_category_tag_pairs.add((record_category, tag))

    # Convert the set to a list and sort it by record_category and tag
    sorted_pairs = sorted(list(processed_record_category_tag_pairs), key=lambda x: (x[0], x[1]))

    do_block_sql = """
    DO $$
    DECLARE
        rec_cat config.marc_record_type;
        rec_tag TEXT;
    BEGIN
        {}
    END $$;
    """.format(
        '\n    '.join(
            """
            rec_cat := '{}'::config.marc_record_type;
            rec_tag := '{}';
            IF NOT EXISTS (
                SELECT 1
                FROM config.marc_field
                WHERE marc_record_type = rec_cat AND tag = rec_tag
            ) THEN
                RAISE INFO 'Missing combination: record_category=%, tag=%', rec_cat, rec_tag;
            END IF;
            """.format(record_category, tag)
            for record_category, tag in sorted_pairs
        )
    )

    write_out_file('test_config_marc_field.sql', do_block_sql)
