import { Component, Input } from '@angular/core';
import { BibRecordSummary, RecordDisplayEntry } from './bib-record.service';
import { FormatsAndEditionsDisplayComponent } from './formats-and-editions-display/formats-and-editions-display.component';
import { FieldDisplayComponent } from './field-display/field-display.component';
import { StaffRecordSummaryLayoutComponent } from './staff-record-summary-view/staff-record-summary-layout.component';
import { HoldCountDisplayComponent } from './hold-count-display/hold-count-display.component';
import { ItemCountDisplayComponent } from './item-count-display/item-count-display.component';
import { NgComponentOutlet } from '@angular/common';
import { ResultsMetadataLayoutComponent } from '@eg/staff/catalog/result/results-metadata-layout.component';


// This component is responsible for displaying a column of metadata
// taken from a BibRecordSummary, such as those in the catalog
// search results or record staff view
@Component({
    selector: 'eg-metadata-column',
    standalone: true,
    imports: [
        FieldDisplayComponent,
        FormatsAndEditionsDisplayComponent, HoldCountDisplayComponent,
        ItemCountDisplayComponent, NgComponentOutlet
    ],
    templateUrl: './metadata-column.component.html'
})
export class MetadataColumnComponent {
  @Input() column: RecordDisplayEntry[] = [];
  @Input() summary: BibRecordSummary;
  @Input() view: 'staff_view'|'search_result' = 'staff_view';


  // eslint-disable-next-line getter-return
  protected get layoutComponent() {
      switch(this.view) {
          case 'staff_view':
              return StaffRecordSummaryLayoutComponent;
          case 'search_result':
              return ResultsMetadataLayoutComponent;
      }
  }

  protected get inline(): boolean {
      return this.view === 'search_result';
  }
}
