import { Component, OnInit, Input, inject } from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { StaffCommonModule } from '@eg/staff/common.module';

/* Add/Remove Secondary Groups */

@Component({
    selector: 'eg-patron-secondary-groups',
    templateUrl: 'secondary-groups.component.html',
    imports: [StaffCommonModule]
})

export class SecondaryGroupsDialogComponent
    extends DialogComponent implements OnInit {
    private modal: NgbModal;
    private toast = inject(ToastService);
    private net = inject(NetService);
    private idl = inject(IdlService);
    private evt = inject(EventService);
    private pcrud = inject(PcrudService);
    private org = inject(OrgService);
    private auth = inject(AuthService);


    @Input() secondaryGroups: IdlObject[] = []; // pgt
    selectedProfile: IdlObject;
    pendingGroups: IdlObject[];

    constructor() {
        const modal = inject(NgbModal);

        super(modal);

        this.modal = modal;
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.pendingGroups = [];
            this.selectedProfile = null;
        });
    }

    add() {
        if (this.selectedProfile) {
            this.pendingGroups.push(this.selectedProfile);
            this.selectedProfile = null;
        }
    }

    removePending(grp: IdlObject) {
        this.pendingGroups =
            this.pendingGroups.filter(p => p.id() !== grp.id());
    }

    remove(grp: IdlObject) {
        grp.deleted(true);
    }

    applyChanges() {
        this.close(
            this.pendingGroups.concat(
                this.secondaryGroups.filter(g => !g.isdeleted()))
        );

        // Reset the flags on the group objects so there's no
        // unintended side effects.
        this.secondaryGroups.concat(this.pendingGroups).forEach(grp => {
            grp.isnew(null);
            grp.isdeleted(null);
        });
    }
}

