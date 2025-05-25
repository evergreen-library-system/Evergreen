import {Component, Input} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

/** New hold notify dialog */

@Component({
    selector: 'eg-hold-notify-dialog',
    templateUrl: 'notify-dialog.component.html'
})
export class HoldNotifyDialogComponent extends DialogComponent {
    method: string;
    note: string;

    @Input() holdId: number;

    constructor(
        private modal: NgbModal,
        private idl: IdlService,
        private auth: AuthService,
        private pcrud: PcrudService
    ) { super(modal); }

    createNotify() {
        const notify = this.idl.create('ahn');
        notify.hold(this.holdId);
        notify.notify_staff(this.auth.user().id());
        notify.method(this.method);
        notify.note(this.note);

        this.pcrud.create(notify).toPromise().then(
            resp => this.close(resp), // new notify object
            err => console.error('Could not create notify', err)
        );
    }
}


