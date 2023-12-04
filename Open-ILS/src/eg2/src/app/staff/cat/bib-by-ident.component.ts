import {Component, OnInit, ViewChild, Input, AfterViewInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';

/* Component for retrieving bib records by ID, TCN */

@Component({
    templateUrl: 'bib-by-ident.component.html'
})
export class BibByIdentComponent implements OnInit, AfterViewInit {

    identType: 'id' | 'tcn' = 'id';
    identValue: string;
    notFound = false;
    multiRecordsFound = false;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private pcrud: PcrudService
    ) {}

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.identType = params.get('identType') as 'id' | 'tcn';
        });
    }

    ngAfterViewInit() {
        const node = document.getElementById('bib-ident-value');
        setTimeout(() => node.focus());
    }

    search() {
        if (!this.identValue) { return; }

        this.notFound = false;
        this.multiRecordsFound = false;

        let promise;
        if (this.identType === 'id') {
            promise = this.getById();

        } else if (this.identType === 'tcn') {
            promise = this.getByTcn();
        }

        promise.then(id => {
            if (id === null) {
                this.notFound = true;
            } else {
                this.goToRecord(id);
            }
        });
    }

    getById(): Promise<number> {
        // Confirm the record exists before redirecting.
        return this.pcrud.retrieve('bre', this.identValue).toPromise()
            .then(rec => rec ? rec.id() : null);
    }

    getByTcn(): Promise<number> {
        // Start by searching non-deleted records

        return this.net.request(
            'open-ils.search',
            'open-ils.search.biblio.tcn', this.identValue).toPromise()
            .then(resp => {

                if (resp.count > 0) {
                    return Promise.resolve(resp);
                }

                // No active records, see if we have any deleted records.
                return this.net.request(
                    'open-ils.search',
                    'open-ils.search.biblio.tcn', this.identValue, true
                ).toPromise();

            }).then(resp => {

                if (resp.count) {
                    if (resp.count > 1) {
                        this.multiRecordsFound = true;
                        return null;
                    } else {
                        return resp.ids[0];
                    }
                }

                return null;
            });
    }

    goToRecord(id: number) {
        this.router.navigate([`/staff/catalog/record/${id}`]);
    }
}


