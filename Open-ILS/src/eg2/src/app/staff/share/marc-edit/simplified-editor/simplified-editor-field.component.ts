import {Component, Host, Input, OnInit, AfterViewInit} from '@angular/core';
import {MarcSimplifiedEditorComponent} from './simplified-editor.component';
import {MarcField, MarcSubfield} from '../marcrecord';

/**
 * A field that a user can edit, which will later be
 * compiled into MARC
 */

@Component({
  selector: 'eg-marc-simplified-editor-field',
  template: ''
})
export class MarcSimplifiedEditorFieldComponent implements OnInit, AfterViewInit {

  @Input() tag = 'a';
  @Input() ind1 = ' ';
  @Input() ind2 = ' ';

  subfieldIndex = 1;

  marcVersion: MarcField;

  addSubfield: (code: string, defaultValue?: string) => void;

  constructor(@Host() private editor: MarcSimplifiedEditorComponent) {}

  ngOnInit() {
    this.marcVersion = {
      tag: this.tag,
      subfields: [],
      authValid: false,
      authChecked: false,
      isCtrlField: false,
      isControlfield: () => false,
      indicator: (ind: number) => (ind === 1) ? this.ind1 : this.ind2,
      deleteExactSubfields: (...subfield: MarcSubfield[]) => 0, // not used by the simplified editor
    };

    this.addSubfield = (code: string, defaultValue?: string) => {
      this.marcVersion.subfields.push(
        [
          code,
          defaultValue ? defaultValue : '',
          this.subfieldIndex
        ]
      );
      this.subfieldIndex += 1;

    };
  }

  ngAfterViewInit() {
    this.editor.addField(this.marcVersion);
  }

}



