/* i18n string utility code */

import { Observable, of, map, catchError } from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';

// retrieves a config.i18n_string entry via pcrud
// Import this with: import {getI18nString} from '@eg/share/util/i18ns';
export function getI18nString(pcrud, id: number, defaultString?: string): Observable<string> {
    return pcrud.retrieve('i18ns', id).pipe(
        map((i18n_string: IdlObject) => i18n_string.string()),
        catchError(() => of(defaultString || ('Missing I18N string #' + id) ))
    );
}
