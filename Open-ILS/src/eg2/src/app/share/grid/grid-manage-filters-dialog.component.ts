/* eslint-disable no-empty */
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {Component, Input, OnInit, OnDestroy, ViewChild, Renderer2} from '@angular/core';
import {GridContext} from '@eg/share/grid/grid';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgForm} from '@angular/forms';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {PcrudService} from '@eg/core/pcrud.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {Subject, Subscription, debounceTime, distinctUntilChanged} from 'rxjs';

@Component({
    selector: 'eg-grid-manage-filters-dialog',
    templateUrl: './grid-manage-filters-dialog.component.html'
})

export class GridManageFiltersDialogComponent extends DialogComponent implements OnInit, OnDestroy {

    @Input() gridContext: GridContext;

    subscriptions: Subscription[] = [];

    saveFilterName = '';
    saveFilterNameModelChanged: Subject<string> = new Subject<string>();
    nameCollision = false;

    filterSetEntries: ComboboxEntry[] = [];

    @ViewChild('manageFiltersForm', { static: false}) manageFiltersForm: NgForm;
    @ViewChild('namedFilterSetSelector', { static: true}) namedFilterSetSelector: ComboboxComponent;

    constructor(
        private modal: NgbModal,
        private pcrud: PcrudService,
        private renderer: Renderer2,
        private store: ServerStoreService,
    ) {
        super(modal);
        if (this.modal) {} // noop for delinting
    }

    ngOnInit() {

        this.subscriptions.push( this.onOpen$.subscribe(
            _ => {
                const el = this.renderer.selectRootElement('#session_name');
                if (el) { el.focus(); el.select(); }
            }
        ));

        this.subscriptions.push(
            this.saveFilterNameModelChanged
                .pipe(
                    // eslint-disable-next-line no-magic-numbers
                    debounceTime(300),
                    distinctUntilChanged()
                )
                .subscribe( newText => {
                    this.saveFilterName = newText;
                    this.nameCollision = false;
                    if (newText !== '') {
                        this.store.getItem('eg.grid.filters.' + this.gridContext.persistKey).then( setting => {
                            if (setting) {
                                if (setting[newText]) {
                                    this.nameCollision = true;
                                }
                            }
                        });
                    }
                })
        );

        this.refreshEntries();
    }

    ngOnDestroy() {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

    saveFilters() {
        this.gridContext.saveFilters(this.saveFilterName);
        this.refreshEntries();
        this.nameCollision = true;
        this.close();
    }

    disableSaveNameTest(): boolean {
        const isEmpty = (obj: any): boolean => {
            return obj && Object.keys(obj).length === 0;
        };

        return isEmpty(this.gridContext?.dataSource?.filters);
    }

    disableSaveButtonTest(): boolean {
        const isEmpty = (obj: any): boolean => {
            return obj && Object.keys(obj).length === 0;
        };

        return this.nameCollision || this.saveFilterName === '' || isEmpty(this.gridContext?.dataSource?.filters);
    }

    refreshEntries() {
        this.filterSetEntries = [];
        this.store.getItem('eg.grid.filters.' + this.gridContext.persistKey).then( setting => {
            if (setting /* for testing only: && Object.keys( setting ).length > 0 */) {
                Object.keys(setting).forEach( key => {
                    this.filterSetEntries.push({ id: key, label: key });
                });
            } else {
                if (this.gridContext.migrateLegacyFilterSets) {
                    this.attemptLegacyFilterSetMigration();
                }
            }
            if (this.namedFilterSetSelector && this.filterSetEntries.length > 0) {
                this.namedFilterSetSelector.selected = this.filterSetEntries[0];
            }
        });
    }

    legacyFieldMap(legacy_field: string): string {
        if (this.gridContext.idlClass === 'uvuv') {
            if (legacy_field === 'url_id') { return 'url'; }
            if (legacy_field === 'attempt_id') { return 'id'; }
            if (legacy_field === 'res_time') { return 'res_time'; }
            if (legacy_field === 'res_code') { return 'res_code'; }
            if (legacy_field === 'res_text') { return 'res_text'; }
            if (legacy_field === 'req_time') { return 'req_time'; }
            return 'url.' + legacy_field;
        } else {
            if (legacy_field === 'url_id') { return 'id'; }
        }

        return legacy_field;
    }

    legacyOperatorValueMap(field_name: string, field_datatype: string, legacy_operator: string, legacy_value: any): any {
        let operator = legacy_operator;
        let value = legacy_value;
        let filterOperator = legacy_operator;
        let filterValue = legacy_value;
        const filterInputDisabled = false;
        const filterIncludeOrgAncestors = false;
        const filterIncludeOrgDescendants = false;
        let notSupported = false;
        if (field_datatype) {} // delint TODO: remove this?
        switch(legacy_operator) {
            case '=': case '!=': case '>': case '<': case '>=': case '<=':
                /* same */
                break;
            case 'in': case 'not in':
            case 'between': case 'not between':
                /* not supported, warn user */
                operator = undefined;
                value = undefined;
                filterOperator = '=';
                filterValue = undefined;
                notSupported = true;
                break;
            case 'null':
                operator = '=';
                value = undefined;
                filterOperator = '=';
                filterValue = null;
                break;
            case 'not null':
                operator = '!=';
                value = undefined;
                filterOperator = '!=';
                filterValue = null;
                break;
            case 'like': case 'not like':
                value = '%' + filterValue + '%';
                /* not like needs special handling further below */
                break;
        }
        if (notSupported) {
            return undefined;
        }

        const filter = {};
        const mappedFieldName = this.legacyFieldMap(field_name);
        filter[mappedFieldName] = {};
        if (operator === 'not like') {
            filter[mappedFieldName]['-not'] = {};
            filter[mappedFieldName]['-not'][mappedFieldName] = {};
            filter[mappedFieldName]['-not'][mappedFieldName]['like'] = value;
        } else {
            filter[mappedFieldName][operator] = value;
        }

        const control = {
            isFiltered: true,
            filterValue: filterValue,
            filterOperator: filterOperator,
            filterInputDisabled: filterInputDisabled,
            filterIncludeOrgAncestors: filterIncludeOrgAncestors,
            filterIncludeOrgDescendants: filterIncludeOrgDescendants
        };

        return [ filter, control ];
    }

    attemptLegacyFilterSetMigration() {
    // The legacy interface allows you to define multiple filters for the same column, which our current filters
    // do not support (well, the dataSource.filters part can, but not the grid.context.filterControls).  The legacy
    // filters also have an unintuitive additive behavior if you do that.  We should take the last filter and warn
    // the user if this happens.  None of the filters for date columns is working correctly in the legacy UI, so no
    // need to map those.  We also not able to support between, not between, in, and not in.
        this.pcrud.search('cfdfs', {'interface':this.gridContext.migrateLegacyFilterSets},{},{'atomic':true}).subscribe(
            (legacySets) => {
                legacySets.forEach( (s:any) => {
                    const obj = {
                        'filters' : {},
                        'controls' : {}
                    };
                    console.log('migrating legacy set ' + s.name(), s );
                    JSON.parse( s.filters() ).forEach( (f:any) => {
                        const mappedFieldName = this.legacyFieldMap(f.field);
                        const c = this.gridContext.columnSet.getColByName( mappedFieldName );
                        if (c) {
                            const r = this.legacyOperatorValueMap(f.field, c.datatype, f.operator, f.value || f.values);
                            obj['filters'][mappedFieldName] = [ r[0] ];
                            obj['controls'][mappedFieldName] = r[1];
                        } else {
                            console.log('with legacy set ' + s.name()
                                + ', column not found for ' + f.field + ' (' + this.legacyFieldMap( f.field) + ')');
                        }
                    });
                    if (Object.keys(obj.filters).length > 0) {
                        this.store.getItem('eg.grid.filters.' + this.gridContext.persistKey).then( setting => {
                            setting ||= {};
                            setting[s.name()] = obj;
                            this.store.setItem('eg.grid.filters.' + this.gridContext.persistKey, setting).then( res => {
                                this.refreshEntries();
                                console.log('save toast here',res);
                            });
                        });
                    }
                });
            }
        );
    }
}
