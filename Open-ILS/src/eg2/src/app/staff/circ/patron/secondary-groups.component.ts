import {Component, OnInit, Input} from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

/* Add/Remove Secondary Groups */

@Component({
    selector: 'eg-patron-secondary-groups',
    templateUrl: 'secondary-groups.component.html'
})

export class SecondaryGroupsDialogComponent
    extends DialogComponent implements OnInit {

    @Input() secondaryGroups: IdlObject[] = []; // pgt
    selectedProfile: IdlObject;
    pendingGroups: IdlObject[];

    constructor(
        private modal: NgbModal,
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private evt: EventService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService) {
        super(modal);
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

