import {Component, OnInit} from '@angular/core';
import {of, from, throwError, concatMap, mergeMap} from 'rxjs';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';

@Component({
    templateUrl: 'claims-returned-dialog.component.html',
    selector: 'eg-claims-returned-dialog'
})
export class ClaimsReturnedDialogComponent
    extends DialogComponent implements OnInit {

    barcodes: string[];
    returnDate: string;
    patronExceeds: boolean;
    completed: {[barcode: string]: boolean} = {};

    constructor(
        private modal: NgbModal,
        private net: NetService,
        private auth: AuthService,
        private evt: EventService
    ) { super(modal); }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.returnDate = new Date().toISOString();
            this.patronExceeds = false;
            this.completed = {};
        });
    }

    modifyBatch(override?: boolean) {

        let method = 'open-ils.circ.circulation.set_claims_returned';
        if (override) { method += '.override'; }

        from(this.barcodes).pipe(concatMap(barcode => {

            return this.net.request(
                'open-ils.circ', method, this.auth.token(),
                {barcode: barcode, backdate: this.returnDate}
            ).pipe(mergeMap(response => {

                if (Number(response) === 1) {
                    this.completed[barcode] = true;
                    return of(true);
                }

                console.warn(response);

                const evt = this.evt.parse(response);

                if (evt &&
                    evt.textcode === 'PATRON_EXCEEDS_CLAIMS_RETURN_COUNT') {
                    this.patronExceeds = true;
                    return throwError('Patron Exceeds Count'); // stop it all
                }

                return of(false);
            }));
        }))
            .subscribe(
                {
                    error: (err: unknown) => console.log('Claims returned stopped with', err),
                    complete: () => this.close(Object.keys(this.completed).length)
                }
            );
    }

    confirmExceeds() {
        this.barcodes = this.barcodes.filter(b => !this.completed[b]);
        this.modifyBatch(true);
    }
}


