/**
 * The type of content included in a particular display entry.  It should
 * match the config.ui_record_display_entry_content_type ENUM in the db.
 */
export type DisplayEntryContentType = 'field' | 'formats_and_editions' | 'hold_counts' | 'item_counts';

export function contentTypeLabel(type: DisplayEntryContentType) {
    switch (type) {
        case 'field':
            return $localize`Field`;
        case 'formats_and_editions':
            return $localize`Formats and editions`;
        case 'hold_counts':
            return $localize`Hold counts`;
        case 'item_counts':
            return $localize`Item counts`;
    }
}
