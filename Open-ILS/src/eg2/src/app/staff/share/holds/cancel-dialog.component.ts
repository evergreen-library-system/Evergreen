import {Component, Input, ViewChild} from '@angular/core';
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
import {WorkLogService, WorkLogEntry} from '@eg/staff/share/worklog/worklog.service';

/**
 * Dialog for canceling hold requests.
 */

@Component({
    selector: 'eg-hold-cancel-dialog',
    templateUrl: 'cancel-dialog.component.html'
})

export class HoldCancelDialogComponent
    extends DialogComponent {

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
        private auth: AuthService,
        private worklog: WorkLogService) {
        super(modal); // required for subclassing
        this.cancelReasons = [];
    }

    // Avoid fetching cancel reasons in ngOnInit becaues that causes
    // them to load regardless of whether the dialog is ever used.
    open(args: NgbModalOptions): Observable<boolean> {
        this.numSucceeded = 0;
        this.numFailed = 0;

        if (this.cancelReasons.length === 0) {
            this.pcrud.retrieveAll('ahrcc', {}, {atomic: true}).toPromise()
                .then(reasons => {
                    this.cancelReasons = reasons
                    // only display reasons for manually canceling holds
                        .filter(r => 't' === r.manual())
                        .map(r => ({id: r.id(), label: r.label()}));
                });
        }

        return super.open(args);
    }

    async cancelNext(ids: number[]): Promise<any> {
        if (ids.length === 0) {
            return Promise.resolve();
        }

        const holdId = ids.pop();

        return this.net.request(
            'open-ils.circ', 'open-ils.circ.hold.cancel',
            this.auth.token(), holdId,
            this.cancelReason, this.cancelNote
        ).toPromise().then(
            async(result) => {
                if (Number(result) === 1) {
                    this.numSucceeded++;
                    this.toast.success(await this.successMsg.current());
                    await this.recordHoldCancelWorkLog(holdId);
                } else {
                    this.numFailed++;
                    console.error(this.evt.parse(result));
                    this.toast.warning(await this.errorMsg.current());
                }
                return this.cancelNext(ids);
            }
        );
    }

    async recordHoldCancelWorkLog(holdId: number) {
        try {
            // Load work log settings first
            await this.worklog.loadSettings();

            // Request hold details
            const details = await this.net.request(
                'open-ils.circ', 'open-ils.circ.hold.details.retrieve',
                this.auth.token(), holdId, {
                    'suppress_notices': true,
                    'suppress_transits': true,
                    'suppress_mvr': true,
                    'include_usr': true
                }).toPromise();

            //console.log('details', details);
            const entry: WorkLogEntry = {
                'action': 'canceled_hold',
                'hold_id': holdId,
                'patron_id': details.hold.usr().id(),
                'user': details.patron_last,
                'item': details.copy ? details.copy.barcode() : null,
                'item_id': details.copy ? details.copy.id() : null
            };

            this.worklog.record(entry);

        } catch (error) {
            console.error('Error in work log process:', error);
        }
    }

    async cancelBatch(): Promise<any> {
        this.numSucceeded = 0;
        this.numFailed = 0;
        const ids = [].concat(this.holdIds);
        await this.cancelNext(ids);
        this.close(this.numSucceeded > 0);
    }
}



