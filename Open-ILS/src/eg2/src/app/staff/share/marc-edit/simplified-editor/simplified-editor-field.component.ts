import {Component, Host, Input, OnInit} from '@angular/core';
import {MarcSimplifiedEditorComponent} from './simplified-editor.component';
import {MarcSubfield} from '../marcrecord';

/**
 * A field that a user can edit, which will later be
 * compiled into MARC
 */

@Component({
  selector: 'eg-marc-simplified-editor-field',
  template: '<ng-template></ng-template>'
})
export class MarcSimplifiedEditorFieldComponent implements OnInit {

  @Input() tag: string;
  @Input() subfield: string;
  @Input() defaultValue: string;

  constructor(@Host() private editor: MarcSimplifiedEditorComponent) {}

  ngOnInit() {
      this.editor.addField({
          tag: this.tag,
          subfields: [[
              this.subfield,
              this.defaultValue ? this.defaultValue : '',
              0
          ]],
          authValid: false,
          authChecked: false,
          isCtrlField: false,
          isControlfield: () => false,
          indicator: (ind: number) => '0',
          deleteExactSubfields: (...subfield: MarcSubfield[]) => 0,
      });
  }

}



