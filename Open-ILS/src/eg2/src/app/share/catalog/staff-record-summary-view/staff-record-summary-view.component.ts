import { Component, Input } from '@angular/core';
import { BibRecordSummary } from '../bib-record.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { MetadataColumnComponent } from '../metadata-column.component';

@Component({
    selector: 'eg-staff-record-summary-view',
    standalone: true,
    imports: [
        StaffCommonModule,
        MetadataColumnComponent
    ],
    templateUrl: './staff-record-summary-view.component.html'
})
// This component is responsible for displaying a bib record summary
export class StaffRecordSummaryViewComponent {
    @Input() summary: BibRecordSummary;
}
