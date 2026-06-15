import { inject, Injectable } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { Observable } from 'rxjs';

@Injectable({providedIn: 'root'})
export class HoldNotesService {
    private pcrud = inject(PcrudService);

    addNote(note: IdlObject): Observable<IdlObject> {
        return this.pcrud.create(note);
    }
    deleteNote(note: IdlObject): Observable<IdlObject> {
        return this.pcrud.remove(note);
    }
    getNotes(holdId: number): Observable<IdlObject[]> {
        return this.pcrud.search('ahrn', {hold: holdId}, null, {atomic: true});
    }
}
