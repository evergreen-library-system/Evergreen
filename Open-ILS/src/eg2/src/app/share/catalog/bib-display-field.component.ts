import {Component, OnInit, Input, ViewEncapsulation} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {BibRecordService, BibRecordSummary
    } from '@eg/share/catalog/bib-record.service';

/* Display content from a bib summary display field.  If highlight
 * data is avaialble, it will be used in lieu of the plan display string.
 *
 * <eg-bib-display-field field="title" [summary]="summary"
 *  [usePlaceholder]="true"></eg-bib-display-field>
 */

// non-collapsing space
const PAD_SPACE = ' '; // U+2007

@Component({
  selector: 'eg-bib-display-field',
  templateUrl: 'bib-display-field.component.html',
  styleUrls: ['bib-display-field.component.css'],
  encapsulation: ViewEncapsulation.None // required for search highlighting
})
export class BibDisplayFieldComponent implements OnInit {

    @Input() summary: BibRecordSummary;
    @Input() field: string; // display field name

    // Used to join multi fields
    @Input() joiner: string;

    // If true, replace empty values with a non-collapsing space.
    @Input() usePlaceholder: boolean;

    constructor() {}

    ngOnInit() {}

    // Returns an array of display values which may either be
    // plain string values or strings with embedded HTML markup
    // for search results highlighting.
    getDisplayStrings(): string[] {
        const replacement = this.usePlaceholder ? PAD_SPACE : '';

        if (!this.summary) { return [replacement]; }

        const scrunch = (value) => {
            if (Array.isArray(value)) {
                return value;
            } else {
                return [value || replacement];
            }
        };

        return scrunch(
            this.summary.displayHighlights[this.field] ||
            this.summary.display[this.field]
        );
    }
}


