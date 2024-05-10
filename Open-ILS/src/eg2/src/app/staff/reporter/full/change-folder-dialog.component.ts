/* eslint-disable */
import {Input, Component} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {ReporterService} from '../share/reporter.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'change-folder-dialog',
    templateUrl: './change-folder-dialog.component.html'
})

export class ChangeFolderDialogComponent extends DialogComponent {

    @Input() currentFolder: IdlObject = null;
    newFolder: IdlObject = null;

    constructor(
        private modal: NgbModal,
        public RSvc: ReporterService
    ) {
        super(modal);
    }

    folderNodeSelected(node) {
        if(node.callerData.folderIdl) {
            this.newFolder = node.callerData.folderIdl;
        }
    }
}


