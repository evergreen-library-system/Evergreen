import {Component, Input} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalRef, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {MarcEditContext, MARC_RECORD_TYPE} from './editor-context';


/**
 * Spawn a MARC editor within a dialog.
 */

@Component({
    selector: 'eg-marc-editor-dialog',
    templateUrl: './editor-dialog.component.html'
})

export class MarcEditorDialogComponent
    extends DialogComponent {

    @Input() context: MarcEditContext;
    @Input() recordXml: string;
    @Input() recordType: MARC_RECORD_TYPE = 'biblio';

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        private net: NetService) {
        super(modal);
    }

    handleRecordSaved(saved) {
        this.close(saved);
    }
}


