import { inject, Injectable } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { Observable, of, tap } from 'rxjs';

@Injectable({providedIn: 'root'})
// This service is responsible for providing configuration information
// about configured bibliographic fields
export class BibFieldService {
    private pcrud = inject(PcrudService);
    private _displayFields: IdlObject[];

    // Cache cdfm entries in memory, so that we aren't constantly fetching
    // them, but a user can still refresh the client to get any updates
    get displayFields(): Observable<IdlObject[]> {
        if (this._displayFields) { return of(this._displayFields); }
        return this.pcrud.retrieveAll('cdfm', {
            flesh: 1, flesh_fields: {'cdfm': ['field']}, order_by: {cmf: ['label']}
        }, {atomic: true}).pipe(
            tap((values: IdlObject[]) => this._displayFields = values)
        );
    }

    recordDisplayEntries(type: 'search_result'|'staff_view'): Observable<IdlObject[]> {
        return this.pcrud.search('curde',
            {type: type},
            {
                flesh: 2,
                flesh_fields: {curde: ['field'], cmf: ['display_field_map']},
                order_by: [{class: 'curde', field: 'col_pos'}, {class: 'curde', field: 'id'}]
            }, {atomic: true});
    }
}
