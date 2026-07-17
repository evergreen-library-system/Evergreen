import { Component, OnInit, Input } from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import { ProfileSelectComponent } from '@eg/staff/share/patron/profile-select.component';

/* Add/Remove Secondary Groups */

@Component({
    selector: 'eg-patron-secondary-groups',
    templateUrl: 'secondary-groups.component.html',
    imports: [StaffCommonModule, ProfileSelectComponent]
})

export class SecondaryGroupsDialogComponent
    extends DialogComponent implements OnInit {


    @Input() secondaryGroups: IdlObject[] = []; // pgt
    selectedProfile: IdlObject;
    pendingGroups: IdlObject[];

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

