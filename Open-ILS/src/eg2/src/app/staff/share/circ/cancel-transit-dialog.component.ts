import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {from, concatMap, tap} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {StringComponent} from '@eg/share/string/string.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ToastService} from '@eg/share/toast/toast.service';

/** Route Item Dialog */

@Component({
    templateUrl: 'cancel-transit-dialog.component.html',
    selector: 'eg-cancel-transit-dialog'
})
export class CancelTransitDialogComponent extends DialogComponent implements OnInit {

    @Input() transitIds: number[];
    numTransits: number;

    @ViewChild('success') success: StringComponent;
    @ViewChild('failure') failure: StringComponent;

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private net: NetService,
        private evt: EventService,
        private toast: ToastService
    ) { super(modal); }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.numTransits = this.transitIds.length;
        });
    }

    proceed() {

        let changesMade = false;
        let error = false;

        from(this.transitIds).pipe(concatMap(id => {
            return this.net.request(
                'open-ils.circ',
                'open-ils.circ.transit.abort',
                this.auth.token(), {transitid: id}
            ).pipe(tap(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    error = true;
                    this.toast.danger(this.failure.text);
                    console.error(evt);
                } else {
                    changesMade = true;
                }
            }));
        })).subscribe({ complete: () => {
            if (changesMade && !error) {
                this.toast.success(this.success.text);
            }
            this.close(changesMade);
        } });
    }
}


