import {Component, OnInit, Input} from '@angular/core';
import {OrgService} from '@eg/core/org.service';
import {BibRecordService, BibRecordSummary
} from '@eg/share/catalog/bib-record.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {StaffCatalogService} from '@eg/staff/catalog/catalog.service';
import { firstValueFrom, Observable } from 'rxjs';

@Component({
    selector: 'eg-bib-staff-view',
    templateUrl: 'bib-staff-view.component.html',
    styleUrls: ['bib-staff-view.component.css']
})
export class BibStaffViewComponent implements OnInit {

    recId: number;
    initDone = false;

    // True / false if the display is vertically expanded
    private _exp: boolean;
    set expand(e: boolean) {
        this._exp = e;
        if (this.initDone) {
            this.saveExpandState();
        }
    }
    get expand(): boolean { return this._exp; }

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.loadSummary();
        }
    }

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
        private org: OrgService,
        private store: ServerStoreService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {

        this.store.getItem('eg.cat.record.staff-view.collapse')
            .then(value => this.expand = !value)
            .then(_ => this.cat.fetchCcvms())
            .then(_ => {
                if (this.recId) {
                // ignore any existing this.summary, always refetch
                    return this.loadSummary();
                }
            }).then(_ => this.initDone = true);
    }

    saveExpandState() {
        this.store.setItem('eg.cat.record.staff-view.collapse', !this.expand);
    }

    loadSummary(): Promise<any> {
        const summaryArgs: [number, number, boolean, number?] = [
            this.recId,
            this.staffCat.searchContext.searchOrg.id(),
            true, // isStaff
        ];
        if (this.staffCat.searchContext.currentLasso()) {
            summaryArgs.push(this.staffCat.searchContext.currentLasso());
        }
        return firstValueFrom(this.bib.getBibSummary(...summaryArgs))
            .then(summary => {
                this.summary = summary;
                return summary.getBibCallNumber();
            });
    }

    orgName(itemCount: any): Observable<string> {
        return this.cat.orgOrLassoName(itemCount);
    }

    iconFormatLabel(code: string): string {
        return this.cat.iconFormatLabel(code);
    }
}


