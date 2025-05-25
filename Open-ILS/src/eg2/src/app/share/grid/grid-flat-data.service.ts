import {Injectable} from '@angular/core';
import {Observable, throwError} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {GridContext, GridColumnSort} from './grid';
import {Pager} from '@eg/share/util/pager';

interface FlatQueryFields {
    [name: string]: string;
}


@Injectable()
export class GridFlatDataService {

    constructor(
        private net: NetService,
        private auth: AuthService
    ) {}


    getRows(gridContext: GridContext,
        query: any, pager: Pager, sort: GridColumnSort[]): Observable<any> {

        if (!gridContext.idlClass) {
            return throwError('GridFlatDataService requires an idlClass');
        }

        const fields = this.compileFields(gridContext);
        const flatSort = sort.map(s => {
            const obj: any = {};
            obj[s.name] = s.dir;
            return obj;
        });

        return this.net.request(
            'open-ils.fielder',
            'open-ils.fielder.flattened_search',
            this.auth.token(), gridContext.idlClass,
            fields, query, {
                sort: flatSort,
                limit: pager.limit,
                offset: pager.offset
            }
        );
    }

    compileFields(gridContext: GridContext): FlatQueryFields {
        const fields: FlatQueryFields = {};

        gridContext.columnSet.requiredColumns().forEach(col => {
            // Verify the column describes a proper IDL field
            const path = col.path || col.name;
            const info = gridContext.columnSet.idlInfoFromDotpath(path);
            if (info) { fields[col.name] = path; }
        });

        return fields;
    }
}

