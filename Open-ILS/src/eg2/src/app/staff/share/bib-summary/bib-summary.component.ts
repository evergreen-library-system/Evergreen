import {Component, OnInit, Input} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';

@Component({
  selector: 'eg-bib-summary',
  templateUrl: 'bib-summary.component.html',
  styles: ['.eg-bib-summary .card-header {padding: .25rem .5rem}']
})
export class BibSummaryComponent implements OnInit {

    initDone = false;
    expandDisplay = true;
    @Input() set expand(e: boolean) {
        this.expandDisplay = e;
    }

    // If provided, the record will be fetched by the component.
    @Input() recordId: number;

    // Otherwise, we'll use the provided bib summary object.
    summary: BibRecordSummary;
    @Input() set bibSummary(s: any) {
        this.summary = s;
        if (this.initDone && this.summary) {
            this.summary.getBibCallNumber();
        }
    }

    constructor(
        private bib: BibRecordService,
        private cat: CatalogService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService
    ) {}

    ngOnInit() {
        this.initDone = true;
        if (this.summary) {
            this.summary.getBibCallNumber();
        } else {
            if (this.recordId) {
                this.loadSummary();
            }
        }
    }

    loadSummary(): void {
        this.bib.getBibSummary(this.recordId).toPromise()
        .then(summary => {
            summary.getBibCallNumber();
            this.bib.fleshBibUsers([summary.record]);
            this.summary = summary;
            console.log(this.summary.display);
        });
    }

    orgName(orgId: number): string {
        if (orgId) {
            return this.org.get(orgId).shortname();
        }
    }

}


