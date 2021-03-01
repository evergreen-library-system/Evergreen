import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/* Dialog for modifying circulation due dates. */

@Component({
  selector: 'eg-due-date-dialog',
  templateUrl: 'due-date-dialog.component.html'
})

export class DueDateDialogComponent
    extends DialogComponent implements OnInit {

    @Input() circs: IdlObject[] = [];
    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    dueDateIsValid = false;
    dueDateIso: string;
    nowTime: number;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private pcrud: PcrudService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.dueDateIso = new Date().toISOString();
            this.nowTime = new Date().getTime();
        });
    }

    dueDateChange(iso: string) {
        if (iso && Date.parse(iso) > this.nowTime) {
            this.dueDateIso = iso;
        } else {
            this.dueDateIso = null;
        }
    }
}
