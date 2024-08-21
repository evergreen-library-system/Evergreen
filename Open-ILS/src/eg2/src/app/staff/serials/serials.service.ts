import { inject } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { StoreService } from '@eg/core/store.service';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { Observable, map, of, reduce, tap, toArray } from 'rxjs';

// This class is responsible for fetching and parsing data that is used
// in the Serials module
export class SerialsService {
    private pcrud = inject(PcrudService);
    private store = inject(StoreService);
    private org = inject(OrgService);
    private callNumberCache: { [bibRecordId: number]: {[orgUnitId: number]: IdlObject[]}} = {};

    callNumberPrefixesAsComboboxEntries$(): Observable<ComboboxEntry[]> {
        return this.affixesAsComboboxEntries('acnp');
    }

    callNumbersAsComboboxEntries$(bibRecordId: number, orgUnitId: number): Observable<ComboboxEntry[]> {
        return this.retrieveCallNumberData$(bibRecordId, orgUnitId).pipe(
            map(callNumbers => {
                return callNumbers.map(callNumber => {
                    return {id: callNumber.id(), label: callNumber.label()};
                });
            })
        );
    }

    callNumberSuffixesAsComboboxEntries$(): Observable<ComboboxEntry[]> {
        return this.affixesAsComboboxEntries('acns');
    }

    defaultCallNumberPrefix$(bibRecordId: number, orgUnitId: number): Observable<ComboboxEntry|null> {
        return this.retrieveCallNumberData$(bibRecordId, orgUnitId).pipe(
            map(callNumbers => {
                if (callNumbers[0] && this.isValidAffix(callNumbers[0].prefix())) {
                    return {id: callNumbers[0].prefix().id(), label: callNumbers[0].prefix().label()};
                }
                return null;
            })
        );
    }

    defaultCallNumber$(bibRecordId: number, orgUnitId: number): Observable<ComboboxEntry|null> {
        return this.retrieveCallNumberData$(bibRecordId, orgUnitId).pipe(
            map(callNumbers => {
                // Take the most recent call number (the first one, since it is ordered by create_date DESC)
                if (callNumbers[0]) {
                    return {id: callNumbers[0].id(), label: callNumbers[0].label() };
                }
                return null;
            })
        );
    }

    defaultCallNumberSuffix$(bibRecordId: number, orgUnitId: number): Observable<ComboboxEntry|null> {
        return this.retrieveCallNumberData$(bibRecordId, orgUnitId).pipe(
            map(callNumbers => {
                if (callNumbers[0] && this.isValidAffix(callNumbers[0].suffix())) {
                    return {id: callNumbers[0].suffix().id(), label: callNumbers[0].suffix().label()};
                }
                return null;
            })
        );
    }

    private retrieveCallNumberData$(bibRecordId: number, orgUnitId: number): Observable<IdlObject[]> {
        if(this.callNumberCache[bibRecordId] && this.callNumberCache[bibRecordId][orgUnitId]) {
            return of(this.callNumberCache[bibRecordId][orgUnitId]);
        } else {
            return this.pcrud.search('acn', {
                record: bibRecordId,
                deleted: 'f',
                owning_lib: this.org.ancestors(orgUnitId, true),
                label: {'!=': '##URI##'}
            }, {
                flesh: 1,
                flesh_fields: { acn: ['prefix', 'suffix'] },
                order_by : [{class:'acn', field:'create_date', direction:'desc'}],
                distinct: 'true',
                select: {
                    acn: ['id', 'label', 'prefix', 'suffix'],
                    acnp: ['id', 'label'],
                    acns: ['id', 'label'],
                }
            }).pipe(
                toArray(),
                tap(callNumbers => {
                    if (!this.callNumberCache[bibRecordId]) {
                        this.callNumberCache[bibRecordId] = {};
                    }
                    this.callNumberCache[bibRecordId][orgUnitId] = callNumbers;
                })
            );
        }
    }

    shouldShowCallNumberAffixes(): boolean {
        const storedValue = this.store.getLocalItem('serials.receive.show_affixes');
        return (storedValue === null) ? true : storedValue;
    }

    storeCallNumberAffixPreference(preference: boolean): void {
        this.store.setLocalItem('serials.receive.show_affixes', preference);
    }

    private isValidAffix(affix: IdlObject) {
        return (affix?.id() && affix?.id() !== -1);
    }

    private affixesAsComboboxEntries(idlClass: string) {
        const select = {};
        select[idlClass] = ['id', 'label'];
        return this.pcrud.search(idlClass, {id: {'>': 0}}, {
            select: select
        }).pipe(
            reduce((affixes: ComboboxEntry[], prefix) => {
                if(prefix.label() && !affixes.map((existing) => existing.label).includes(prefix.label())) {
                    affixes.push({id: prefix.id(), label: prefix.label()});
                }
                return affixes;
            }, [])
        );
    }
}
