import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';


/**
 * Dialog for marking items missing.
 */

@Component({
  selector: 'eg-mark-missing-dialog',
  templateUrl: 'mark-missing-dialog.component.html'
})

export class MarkMissingDialogComponent
    extends DialogComponent implements OnInit {

    @Input() copyIds: number[];

    numSucceeded: number;
    numFailed: number;

    @ViewChild('successMsg', { static: true })
        private successMsg: StringComponent;

    @ViewChild('errorMsg', { static: true })
        private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {}

    async markOneItemMissing(ids: number[]): Promise<any> {
        if (ids.length === 0) {
            return Promise.resolve();
        }

        const id = ids.pop();

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.mark_item_missing',
            this.auth.token(), id
        ).toPromise().then(async(result) => {
            if (Number(result) === 1) {
                this.numSucceeded++;
                this.toast.success(await this.successMsg.current());
            } else {
                this.numFailed++;
                console.error('Mark missing failed ', this.evt.parse(result));
                this.toast.warning(await this.errorMsg.current());
            }
            return this.markOneItemMissing(ids);
        });
    }

    async markItemsMissing(): Promise<any> {
        this.numSucceeded = 0;
        this.numFailed = 0;
        const ids = [].concat(this.copyIds);
        await this.markOneItemMissing(ids);
        this.close(this.numSucceeded > 0);
    }
}



