/* eslint-disable */
import {Input, Component} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {ReporterService} from '../share/reporter.service';

@Component({
    selector: 'folder-share-org-dialog',
    templateUrl: './folder-share-org-dialog.component.html'
})

export class FolderShareOrgDialogComponent extends DialogComponent {

    @Input() currentFolder: IdlObject = null;
    contextOrg = null;

    constructor(
        private RSvc: ReporterService,
        private modal: NgbModal,
        private org: OrgService,
        private auth: AuthService
    ) {
        super(modal);
    }

    notMyOrgs() {
        if (!this.RSvc.globalCanShare) // If they managed to open the dialog, but should not have been able to, just filter all orgs out
            return this.org.list().map(n => n.id());

        let found_it = false;
        let above_me = this.org.ancestors(this.auth.user().ws_ou(), true).filter(n => {
            if (!found_it) { // Have we found the "top" org yet?
                if(n == this.RSvc.topPermOrg.SHARE_REPORT_FOLDER) { // We have now!
                    return found_it = true; // Filter the top one in.
                }
            }
            return !found_it; // Filter those "above"
        });

        return this.org.filterList(
            { notInList: this.org.descendants(this.auth.user().ws_ou(), true).concat(above_me) },
            true
        );
    }
}


