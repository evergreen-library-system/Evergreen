import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/**
 * Dialog for canceling hold requests.
 */

@Component({
  selector: 'eg-hold-cancel-dialog',
  templateUrl: 'cancel-dialog.component.html'
})

export class HoldCancelDialogComponent
    extends DialogComponent implements OnInit {

    @Input() holdIds: number[];
    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    changesApplied: boolean;
    numSucceeded: number;
    numFailed: number;
    cancelReason: number;
    cancelReasons: ComboboxEntry[];
    cancelNote: string;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private pcrud: PcrudService,
        private auth: AuthService) {
        super(modal); // required for subclassing
        this.cancelReasons = [];
    }

    ngOnInit() {
        // Avoid fetching cancel reasons in ngOnInit becaues that causes
        // them to load regardless of whether the dialog is ever used.
    }

    open(args: NgbModalOptions): Observable<boolean> {

        if (this.cancelReasons.length === 0) {
            this.pcrud.retrieveAll('ahrcc', {}, {atomic: true}).toPromise()
            .then(reasons => {
                this.cancelReasons =
                    reasons.map(r => ({id: r.id(), label: r.label()}));
            });
        }

        return super.open(args);
    }

    async cancelNext(ids: number[]): Promise<any> {
        if (ids.length === 0) {
            return Promise.resolve();
        }

        return this.net.request(
            'open-ils.circ', 'open-ils.circ.hold.cancel',
            this.auth.token(), ids.pop(),
            this.cancelReason, this.cancelNote
        ).toPromise().then(
            async(result) => {
                if (Number(result) === 1) {
                    this.numSucceeded++;
                    this.toast.success(await this.successMsg.current());
                } else {
                    this.numFailed++;
                    console.error(this.evt.parse(result));
                    this.toast.warning(await this.errorMsg.current());
                }
                this.cancelNext(ids);
            }
        );
    }

    async cancelBatch(): Promise<any> {
        this.numSucceeded = 0;
        this.numFailed = 0;
        const ids = [].concat(this.holdIds);
        await this.cancelNext(ids);
        this.close(this.numSucceeded > 0);
    }
}



