import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';


/**
 * Dialog for retargeting holds.
 */

@Component({
  selector: 'eg-hold-retarget-dialog',
  templateUrl: 'retarget-dialog.component.html'
})

export class HoldRetargetDialogComponent
    extends DialogComponent implements OnInit {

    @Input() holdIds: number | number[];
    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    changesApplied: boolean;
    numSucceeded: number;
    numFailed: number;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {}

    open(args: NgbModalOptions): Observable<boolean> {
        this.holdIds = [].concat(this.holdIds); // array-ify ints
        return super.open(args);
    }

    async retargetNext(ids: number[]): Promise<any> {
        if (ids.length === 0) {
            return Promise.resolve();
        }

        return this.net.request(
            'open-ils.circ', 'open-ils.circ.hold.reset',
            this.auth.token(), ids.pop()
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
                this.retargetNext(ids);
            }
        );
    }

    async retargetBatch(): Promise<any> {
        this.numSucceeded = 0;
        this.numFailed = 0;
        const ids = [].concat(this.holdIds);
        await this.retargetNext(ids);
        this.close(this.numSucceeded > 0);
    }
}



