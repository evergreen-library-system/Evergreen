import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {empty, of, from, Observable} from 'rxjs';
import {concatMap, tap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {StringComponent} from '@eg/share/string/string.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {CircService, CheckinResult} from './circ.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PrintService} from '@eg/share/print/print.service';

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
        })).subscribe(null, null, () => {
            if (changesMade && !error) {
                this.toast.success(this.success.text);
            }
            this.close(changesMade);
        });
    }
}


