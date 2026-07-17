/* eslint-disable */
import { Input, Component, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {ReporterService} from '../share/reporter.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { TreeComponent } from "@eg/share/tree/tree.component";

@Component({
    selector: 'change-folder-dialog',
    templateUrl: './change-folder-dialog.component.html',
    imports: [StaffCommonModule, TreeComponent]
})

export class ChangeFolderDialogComponent extends DialogComponent {
    RSvc = inject(ReporterService);

    @Input() currentFolder: IdlObject = null;
    newFolder: IdlObject = null;

    folderNodeSelected(node) {
        if(node.callerData.folderIdl) {
            this.newFolder = node.callerData.folderIdl;
        }
    }
}


