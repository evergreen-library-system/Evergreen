import {Directive, Input, Host, OnInit} from '@angular/core';
import {MarcSimplifiedEditorFieldDirective} from './simplified-editor-field.directive';

/**
 * A subfield that a user can edit, which will later be
 * compiled into MARC
 */

@Directive({
  selector: 'eg-marc-simplified-editor-subfield',
})
export class MarcSimplifiedEditorSubfieldDirective implements OnInit {

  @Input() code: string;
  @Input() defaultValue: string;

  constructor(@Host() private field: MarcSimplifiedEditorFieldDirective) {}

  ngOnInit() {
    this.field.addSubfield(this.code, this.defaultValue);
  }

}
