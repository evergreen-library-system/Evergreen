
import { Component, Input } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';

@Component({
    selector: 'eg-serials-note',
    templateUrl: './serials-note.component.html',
    imports: []
})
export class SerialsNoteComponent {
  @Input() note: IdlObject;
}
