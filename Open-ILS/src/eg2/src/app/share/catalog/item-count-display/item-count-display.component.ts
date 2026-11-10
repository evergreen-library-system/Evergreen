import { Component, inject, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { BibRecordSummary, HoldingsSummary } from '../bib-record.service';
import { Observable } from 'rxjs';
import { CatalogService } from '../catalog.service';

@Component({
    selector: 'eg-item-count-display',
    standalone: true,
    imports: [CommonModule],
    templateUrl: './item-count-display.component.html',
    styleUrls: ['./item-count-display.component.css']
})
export class ItemCountDisplayComponent {
    @Input() summary: BibRecordSummary;

    cat = inject(CatalogService);

    orgName(itemCount: HoldingsSummary): Observable<string> {
        return this.cat.orgOrLassoName(itemCount);
    }
}
