import {Component, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';

@Component({
    templateUrl: 'backdate-dialog.component.html',
    selector: 'eg-backdate-dialog'
})
export class BackdateDialogComponent extends DialogComponent implements OnInit {

    circIds: number[];
    backdate: string;
    updateCount = 0;

    constructor(
        private modal: NgbModal,
        private net: NetService,
        private auth: AuthService,
        private evt: EventService
    ) { super(modal); }

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


