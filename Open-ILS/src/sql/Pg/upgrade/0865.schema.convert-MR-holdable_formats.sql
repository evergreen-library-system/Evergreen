
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0865', :eg_version);

-- First, explode the field into constituent parts
WITH format_parts_array AS (
    SELECT  a.id,
            STRING_TO_ARRAY(a.holdable_formats, '-') AS parts
      FROM  action.hold_request a
      WHERE a.hold_type = 'M'
            AND a.fulfillment_time IS NULL
), format_parts_wide AS (
    SELECT  id,
            regexp_split_to_array(parts[1], '') AS item_type,
            regexp_split_to_array(parts[2], '') AS item_form,
            parts[3] AS item_lang
      FROM  format_parts_array
), converted_formats_flat AS (
    SELECT  id, 
            CASE WHEN ARRAY_LENGTH(item_type,1) > 0
                THEN '"0":[{"_attr":"item_type","_val":"' || ARRAY_TO_STRING(item_type,'"},{"_attr":"item_type","_val":"') || '"}]'
                ELSE '"0":""'
            END AS item_type,
            CASE WHEN ARRAY_LENGTH(item_form,1) > 0
                THEN '"1":[{"_attr":"item_form","_val":"' || ARRAY_TO_STRING(item_form,'"},{"_attr":"item_form","_val":"') || '"}]'
                ELSE '"1":""'
            END AS item_form,
            CASE WHEN item_lang <> ''
                THEN '"2":[{"_attr":"item_lang","_val":"' || item_lang ||'"}]'
                ELSE '"2":""'
            END AS item_lang
      FROM  format_parts_wide
) UPDATE action.hold_request SET holdable_formats = '{' ||
        converted_formats_flat.item_type || ',' ||
        converted_formats_flat.item_form || ',' ||
        converted_formats_flat.item_lang || '}'
    FROM converted_formats_flat WHERE converted_formats_flat.id = action.hold_request.id;

COMMIT;

