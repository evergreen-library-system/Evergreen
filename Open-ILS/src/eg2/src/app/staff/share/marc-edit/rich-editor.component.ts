import {Component, Input, Output, OnInit, AfterViewInit, EventEmitter,
    OnDestroy} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';

/**
 * MARC Record rich editor interface.
 */

@Component({
  selector: 'eg-marc-rich-editor',
  templateUrl: './rich-editor.component.html',
  styleUrls: ['rich-editor.component.css']
})

export class MarcRichEditorComponent implements OnInit {

    constructor(
        private idl: IdlService,
        private org: OrgService
    ) {
    }

    ngOnInit() {}
}



