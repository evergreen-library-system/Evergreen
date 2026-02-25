/* eslint-disable */
import { Input, Component, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {ReporterService} from '../share/reporter.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    selector: 'change-folder-dialog',
    templateUrl: './change-folder-dialog.component.html',
    imports: [StaffCommonModule]
})

export class ChangeFolderDialogComponent extends DialogComponent {
    private modal: NgbModal;
    RSvc = inject(ReporterService);


    @Input() currentFolder: IdlObject = null;
    newFolder: IdlObject = null;

    constructor() {
        const modal = inject(NgbModal);

        super(modal);
    
        this.modal = modal;
    }

    folderNodeSelected(node) {
        if(node.callerData.folderIdl) {
            this.newFolder = node.callerData.folderIdl;
        }
    }
}


