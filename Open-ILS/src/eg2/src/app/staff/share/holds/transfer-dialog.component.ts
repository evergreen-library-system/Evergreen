import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {StoreService} from '@eg/core/store.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';


/**
 * Dialog for transferring holds.
 */

@Component({
  selector: 'eg-hold-transfer-dialog',
  templateUrl: 'transfer-dialog.component.html'
})

export class HoldTransferDialogComponent
    extends DialogComponent implements OnInit {

    @Input() holdIds: number | number[];

    @ViewChild('successMsg') private successMsg: StringComponent;
    @ViewChild('errorMsg') private errorMsg: StringComponent;
    @ViewChild('targetNeeded') private targetNeeded: StringComponent;

    transferTarget: number;
    changesApplied: boolean;
    numSucceeded: number;
    numFailed: number;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private store: StoreService,
        private net: NetService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {}

    async open(args: NgbModalOptions): Promise<boolean> {
        this.holdIds = [].concat(this.holdIds); // array-ify ints

        this.transferTarget =
            this.store.getLocalItem('eg.circ.hold.title_transfer_target');

        if (!this.transferTarget) {
            this.toast.warning(await this.targetNeeded.current());
            return Promise.reject('Transfer Target Required');
        }

        return super.open(args);
    }

    async transferHolds(): Promise<any> {
        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.change_title.specific_holds',
            this.auth.token(), this.transferTarget, this.holdIds
        ).toPromise().then(async(result) => {
            if (Number(result) === 1) {
                this.numSucceeded++;
                this.toast.success(await this.successMsg.current());
            } else {
                this.numFailed++;
                console.error('Retarget Failed', this.evt.parse(result));
                this.toast.warning(await this.errorMsg.current());
            }
        });
    }

    async transferBatch(): Promise<any> {
        this.numSucceeded = 0;
        this.numFailed = 0;
        await this.transferHolds();
        this.close(this.numSucceeded > 0);
    }
}



