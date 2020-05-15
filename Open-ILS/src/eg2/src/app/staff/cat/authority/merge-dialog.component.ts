import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';

/**
 * Dialog for merging authority records.
 */

@Component({
  selector: 'eg-authority-merge-dialog',
  templateUrl: 'merge-dialog.component.html'
})

export class AuthorityMergeDialogComponent
    extends DialogComponent implements OnInit {

    // Rows passed from the authority browse grid.
    @Input() authData: any[] = [];

    leadRecord: number;

    @ViewChild('successMsg', {static: true})
        private successMsg: StringComponent;

    @ViewChild('errorMsg', {static: true})
        private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            if (this.authData.length > 0) {
                this.leadRecord = this.authData[0].authority.id();
            }
        });
    }

    merge() {

        const list = this.authData
            .map(data => data.authority.id())
            .filter(id => id !== this.leadRecord);

        this.net.request('open-ils.cat',
            'open-ils.cat.authority.records.merge',
            this.auth.token(), this.leadRecord, list)
        .subscribe(resp => {
            const evt = this.evt.parse(resp);

            if (evt) {
                this.errorMsg.current().then(str => this.toast.warning(str));
                this.close(false);
            } else {
                this.successMsg.current().then(str => this.toast.success(str));
                this.close(true);
            }
        });
    }
}



