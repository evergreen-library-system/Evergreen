import { Component, EventEmitter, Input, Output } from '@angular/core';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';

@Component({
    selector: 'eg-copy-notes-edit',
    templateUrl: './copy-notes-edit.component.html',
    imports: [FmRecordEditorComponent]
})
export class CopyNotesEditComponent {

    constructor() { }

  @Input() recordId: number;
  @Output() doneWithEdits: EventEmitter<any> = new EventEmitter();
}
