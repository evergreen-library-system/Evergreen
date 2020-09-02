import {Directive, Input, Host, OnInit, Component} from '@angular/core';
import {MarcSimplifiedEditorFieldComponent} from './simplified-editor-field.component';

/**
 * A subfield that a user can edit, which will later be
 * compiled into MARC
 */

@Component({
  selector: 'eg-marc-simplified-editor-subfield',
  template: ''
})
export class MarcSimplifiedEditorSubfieldComponent implements OnInit {

  @Input() code: string;
  @Input() defaultValue: string;

  constructor(@Host() private field: MarcSimplifiedEditorFieldComponent) {}

  ngOnInit() {
    this.field.addSubfield(this.code, this.defaultValue);
  }

}
