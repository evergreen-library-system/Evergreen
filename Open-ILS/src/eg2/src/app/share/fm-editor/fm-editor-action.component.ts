import { Component, Input, Output, EventEmitter, OnInit, inject } from '@angular/core';
import {FmRecordEditorComponent} from './fm-editor.component';

@Component({
    selector: 'eg-fm-record-editor-action',
    template: '<ng-template></ng-template>' // no-op
})

export class FmRecordEditorActionComponent implements OnInit {
    private editor = inject(FmRecordEditorComponent, { host: true });


    // unique identifier
    @Input() key: string;

    @Input() label: string;

    @Input() buttonCss = 'btn-outline-dark';

    // Emits the 'key' of the clicked action.
    @Output() actionClick: EventEmitter<string>;

    @Input() disabled: boolean;

    constructor() {
        this.actionClick = new EventEmitter<string>();
    }

    ngOnInit() {
        this.editor.actions.push(this);
    }
}

