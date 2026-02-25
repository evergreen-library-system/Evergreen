import { Component, Input, inject } from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { StaffCommonModule } from '@eg/staff/common.module';

/* Dialog for alerting of an existing open circulation */

@Component({
    selector: 'eg-open-circ-dialog',
    templateUrl: 'open-circ-dialog.component.html',
    imports: [StaffCommonModule]
})

export class OpenCircDialogComponent extends DialogComponent {
    private modal: NgbModal;
    private toast = inject(ToastService);
    private net = inject(NetService);
    private evt = inject(EventService);
    private pcrud = inject(PcrudService);
    private auth = inject(AuthService);


    @Input() sameUser: boolean;
    @Input() circDate: string; // iso
    forgiveFines = false;

    constructor() {
        const modal = inject(NgbModal);

        super(modal); // required for subclassing

        this.modal = modal;
    }
}
