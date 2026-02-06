import {Component, Input} from '@angular/core';
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

    @Input() sameUser: boolean;
    @Input() circDate: string; // iso
    forgiveFines = false;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private pcrud: PcrudService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }
}
