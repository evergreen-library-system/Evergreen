import {Component, Input} from '@angular/core';
import {Observable} from 'rxjs';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {IdlObject} from '@eg/core/idl.service';
import {LineitemService} from './lineitem.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';

@Component({
    selector: 'eg-acq-bib-finder-dialog',
    styleUrls: ['./bib-finder-dialog.component.css'],
    templateUrl: './bib-finder-dialog.component.html'
})

export class BibFinderDialogComponent extends DialogComponent {
    @Input() liId: number;

    queryString: string;
    lineitem: IdlObject;
    results: BibRecordSummary[] = [];
    doingSearch = false;
    bibToDisplay: number;

    constructor(
        private modal: NgbModal,
        private net: NetService,
        private evt: EventService,
        private bib: BibRecordService,
        private liService: LineitemService
    ) {
        super(modal);
    }

    open(args?: NgbModalOptions): Observable<any> {
        if (!args) {
            args = {};
        }

        this.queryString = '';
        this.results.length = 0;
        this.doingSearch = false;
        this.bibToDisplay = null;
        this.liService.getFleshedLineitems([this.liId], {fromCache: true}).subscribe(liStruct => {
            this.lineitem = liStruct.lineitem;
            this.queryString = this._buildDefaultQuery(this.lineitem);
        });
        return super.open(args);
    }

    _buildDefaultQuery(li: IdlObject): string {
        let query = '';
        ['title', 'author'].forEach(field => {
            const attr = this.liService.getFirstAttributeValue(li, field);
            if (attr.length) {
                query += field + ':' + attr + ' ';
            }
        });
        ['isbn', 'issn', 'upc'].forEach(field => {
            const attr = this.liService.getFirstAttributeValue(li, field);
            if (attr.length) {
                query += 'identifier|' + field + ':' + attr + ' ';
            }
        });
        return query;
    }

    submitSearch() {
        this.results.length = 0;
        this.bibToDisplay = null;
        this.doingSearch = true;
        this.net.request(
            'open-ils.search',
            'open-ils.search.biblio.multiclass.query.staff',
            {limit: 15}, this.queryString, 1
        ).subscribe(response => {
            const evt = this.evt.parse(response);
            if (evt) {
                this.doingSearch = false;
                return;
            }
            const ids = response.ids.map(x => x[0]);
            if (ids.length < 1) {
                this.doingSearch = false;
                return;
            }
            const bibSummaries: {[id: number]: BibRecordSummary} = {};
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            this.bib.getBibSummaries(ids).subscribe(
                { next: summary => bibSummaries[summary.id] = summary, error: (err: unknown) => {}, complete: () => {
                    this.doingSearch = false;
                    ids.forEach(id => {
                        if (bibSummaries[id]) {
                            this.results.push(bibSummaries[id]);
                        }
                    });
                } }
            );
        });
    }
}


