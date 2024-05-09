import {Input, Component} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';

@Component({
    selector: 'folder-share-org-dialog',
    templateUrl: './folder-share-org-dialog.component.html'
})

export class FolderShareOrgDialogComponent extends DialogComponent {

    @Input() currentFolder: IdlObject = null;
    contextOrg = null;

    constructor(
        private modal: NgbModal,
        private org: OrgService,
        private auth: AuthService
    ) {
        super(modal);
    }

    notMyOrgs() {
        return this.org.filterList(
            { notInList: this.org.fullPath(this.auth.user().ws_ou(), true) },
            true
        );
    }
}


