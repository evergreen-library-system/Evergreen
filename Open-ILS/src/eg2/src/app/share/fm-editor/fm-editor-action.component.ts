import {Component, Input, Output, EventEmitter, Host, OnInit} from '@angular/core';
import {FmRecordEditorComponent} from './fm-editor.component';

@Component({
  selector: 'eg-fm-record-editor-action',
  template: '<ng-template></ng-template>' // no-op
})

export class FmRecordEditorActionComponent implements OnInit {

    // unique identifier
    @Input() key: string;

    @Input() label: string;

    @Input() buttonCss = 'btn-outline-dark';

    // Emits the 'key' of the clicked action.
    @Output() actionClick: EventEmitter<string>;

    @Input() disabled: boolean;

    constructor(@Host() private editor: FmRecordEditorComponent) {
        this.actionClick = new EventEmitter<string>();
    }

    ngOnInit() {
        this.editor.actions.push(this);
    }
}

