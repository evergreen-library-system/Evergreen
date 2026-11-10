import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RecordDisplayEntry } from '../bib-record.service';
import { ExpandableListComponent, ExpandableListEntry } from '../../expandable-list/expandable-list.component';
@Component({
    selector: 'eg-field-display',
    standalone: true,
    imports: [CommonModule, ExpandableListComponent],
    templateUrl: './field-display.component.html'
})
export class FieldDisplayComponent {
    @Input() field: RecordDisplayEntry;
    @Input() inline: boolean;

    protected get entries(): ExpandableListEntry[] {
        return this.valueArray.map(v => {
            return {
                text: v,
                routerLink: ['/staff', 'catalog', 'search'],
                queryParams: {query: `${this.field.query_field}:${v}`},
                displayLink: this.field.display_as_link
            };
        });
    }

    private get valueArray(): string[] {
        if (this.field?.value === null || this.field?.value === undefined) { return []; }
        return [].concat(this.field.value);
    }
}
