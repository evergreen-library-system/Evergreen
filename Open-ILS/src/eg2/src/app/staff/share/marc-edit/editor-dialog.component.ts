import {Component, forwardRef, Input} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {MarcEditContext, MARC_RECORD_TYPE} from './editor-context';
import { MarcEditorComponent } from './editor.component';


/**
 * Spawn a MARC editor within a dialog.
 */

@Component({
    selector: 'eg-marc-editor-dialog',
    templateUrl: './editor-dialog.component.html',
    imports: [forwardRef(() => MarcEditorComponent)]
})

export class MarcEditorDialogComponent
    extends DialogComponent {

    @Input() context: MarcEditContext;
    @Input() recordXml: string;
    @Input() recordType: MARC_RECORD_TYPE = 'biblio';

    constructor(
        private modal: NgbModal) {
        super(modal);
    }

    handleRecordSaved(saved) {
        this.close(saved);
    }
}


