import { Component, Input, inject } from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { FormsModule } from '@angular/forms';

/** New hold notify dialog */

@Component({
    selector: 'eg-hold-notify-dialog',
    templateUrl: 'notify-dialog.component.html',
    imports: [
        FormsModule
    ]
})
export class HoldNotifyDialogComponent extends DialogComponent {
    private modal: NgbModal;
    private idl = inject(IdlService);
    private auth = inject(AuthService);
    private pcrud = inject(PcrudService);

    method: string;
    note: string;

    @Input() holdId: number;

    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }

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


