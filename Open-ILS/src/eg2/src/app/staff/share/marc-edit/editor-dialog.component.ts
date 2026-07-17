import { Component, forwardRef, Input } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {MarcEditContext, MARC_RECORD_TYPE} from './editor-context';
import { MarcEditorComponent } from './editor.component';
import { FastAddSelectorComponent } from './fast-add-selector.component';


/**
 * Spawn a MARC editor within a dialog.
 */

@Component({
    selector: 'eg-marc-editor-dialog',
    templateUrl: './editor-dialog.component.html',
    imports: [forwardRef(() => MarcEditorComponent), FastAddSelectorComponent]
})

export class MarcEditorDialogComponent
    extends DialogComponent {

    @Input() context: MarcEditContext;
    @Input() recordXml: string;
    @Input() recordType: MARC_RECORD_TYPE = 'biblio';

    handleRecordSaved(saved) {
        this.close(saved);
    }
}


