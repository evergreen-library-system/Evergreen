import { Component, input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { BibRecordSummary } from '../bib-record.service';

// This component is responsible for displaying the hold count from a Bib Summary
@Component({
    selector: 'eg-hold-count-display',
    standalone: true,
    imports: [CommonModule],
    templateUrl: './hold-count-display.component.html',
    styleUrls: ['./hold-count-display.component.css']
})
export class HoldCountDisplayComponent {
    summary = input.required<BibRecordSummary>();
}
