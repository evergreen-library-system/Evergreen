import { Component, OnInit, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: 'backdate-dialog.component.html',
    selector: 'eg-backdate-dialog',
    imports: [StaffCommonModule]
})
export class BackdateDialogComponent extends DialogComponent implements OnInit {
    private modal: NgbModal;
    private net = inject(NetService);
    private auth = inject(AuthService);
    private evt = inject(EventService);


    circIds: number[];
    backdate: string;
    updateCount = 0;

    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.updateCount = 0;
            this.backdate = new Date().toISOString();
        });
    }

    modifyBatch() {
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.post_checkin_backdate.batch',
            this.auth.token(), this.circIds, this.backdate
        ).subscribe(
            { next: res => this.updateCount++, error: (err: unknown) => console.error(err), complete: ()  => this.close(this.backdate) }
        );
    }
}


