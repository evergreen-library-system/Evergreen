import { Component, OnInit, Input, ViewChild, inject } from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import { CommonModule } from '@angular/common';

/* Dialog for modifying circulation due dates. */

@Component({
    selector: 'eg-due-date-dialog',
    templateUrl: 'due-date-dialog.component.html',
    imports: [CommonModule, StringComponent]
})

export class DueDateDialogComponent
    extends DialogComponent implements OnInit {
    private modal: NgbModal;
    private toast = inject(ToastService);
    private net = inject(NetService);
    private evt = inject(EventService);
    private pcrud = inject(PcrudService);
    private auth = inject(AuthService);


    @Input() circs: IdlObject[] = [];
    @Input() allowPastDate = false;

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    dueDateIsValid = false;
    dueDateIso: string;
    nowTime: number;

    constructor() {
        const modal = inject(NgbModal);

        super(modal); // required for subclassing

        this.modal = modal;
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.dueDateIso = new Date().toISOString();
            this.nowTime = new Date().getTime();
        });
    }

    dueDateChange(iso: string) {
        if (iso && (this.allowPastDate || Date.parse(iso) > this.nowTime)) {
            this.dueDateIso = iso;
        } else {
            this.dueDateIso = null;
        }
    }
}
