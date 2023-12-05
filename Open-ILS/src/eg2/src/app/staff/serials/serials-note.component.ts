import { CommonModule } from '@angular/common';
import { Component, Input } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';

@Component({
    selector: 'eg-serials-note',
    templateUrl: './serials-note.component.html',
    standalone: true,
    imports: [CommonModule]
})
export class SerialsNoteComponent {
  @Input() note: IdlObject;
}
