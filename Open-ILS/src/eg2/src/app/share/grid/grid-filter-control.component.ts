import {Component, Input, OnInit, QueryList, ViewChildren} from '@angular/core';
import {GridContext, GridColumn} from './grid';
import {IdlObject} from '@eg/core/idl.service';
import {ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {OrgSelectComponent} from '@eg/share/org-select/org-select.component';
import {OrgService} from '@eg/core/org.service';
import {NgbDropdown} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-grid-filter-control',
  templateUrl: './grid-filter-control.component.html'
})

export class GridFilterControlComponent implements OnInit {

    @Input() context: GridContext;
    @Input() col:     GridColumn;


    @ViewChildren(ComboboxComponent)   filterComboboxes: QueryList<ComboboxComponent>;
    @ViewChildren(DateSelectComponent) dateSelects: QueryList<DateSelectComponent>;
    @ViewChildren(OrgSelectComponent)  orgSelects: QueryList<OrgSelectComponent>;
    @ViewChildren(NgbDropdown)         dropdowns: QueryList<NgbDropdown>;

    constructor(
        private org: OrgService
    ) {}

    ngOnInit() { }

    operatorChanged(col: GridColumn) {
        if (col.filterOperator === 'null' || col.filterOperator === 'not null') {
            col.filterInputDisabled = true;
            col.filterValue = undefined;
        } else {
            col.filterInputDisabled = false;
        }
    }

    applyOrgFilter(org: IdlObject, col: GridColumn) {
        if (org == null) {
            this.clearFilter(col);
            return;
        }
        const ous: any[] = new Array();
        if (col.filterIncludeOrgDescendants || col.filterIncludeOrgAncestors) {
            if (col.filterIncludeOrgAncestors) {
                ous.push(...this.org.ancestors(org, true));
            }
            if (col.filterIncludeOrgDescendants) {
                ous.push(...this.org.descendants(org, true));
            }
        } else {
            ous.push(org.id());
        }
        const filt: any = {};
        filt[col.name] = {};
        const op: string = (col.filterOperator === '=' ? 'in' : 'not in');
        filt[col.name][op] = ous;
        this.context.dataSource.filters[col.name] = [ filt ];
        col.isFiltered = true;
        this.context.reload();
    }

    applyLinkFilter($event, col: GridColumn) {
        if ($event) {
            col.filterValue = $event.id;
            this.applyFilter(col);

        } else {
            // Value was cleared from the combobox
            this.clearFilter(col);
        }
    }

    // TODO: this was copied from date-select and
    // really belongs in a date service
    localDateFromYmd(ymd: string): Date {
        const parts = ymd.split('-');
        return new Date(
            Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }
    applyDateFilter(dateStr: string, col: GridColumn, endDateStr: string) {
        if (col.filterOperator === 'null' || col.filterOperator === 'not null') {
            this.applyFilter(col);
        } else {
            if (dateStr == null) {
                this.clearFilter(col);
                return;
            }
            const date: Date = this.localDateFromYmd(dateStr);
            let date1 = new Date();
            let date2 = new Date();
            const op: string = col.filterOperator;
            const filt: Object = {};
            const filt2: Object = {};
            const filters = new Array();
            if (col.filterOperator === '>') {
                date1 = date;
                date1.setHours(23);
                date1.setMinutes(59);
                date1.setSeconds(59);
                filt[op] = date1.toISOString();
                if (col.name === 'dob') { filt[op] = dateStr; } // special case
                filt2[col.name] = filt;
                filters.push(filt2);
            } else if (col.filterOperator === '>=') {
                date1 = date;
                filt[op] = date1.toISOString();
                if (col.name === 'dob') { filt[op] = dateStr; } // special case
                filt2[col.name] = filt;
                filters.push(filt2);
            } else if (col.filterOperator === '<') {
                date1 = date;
                filt[op] = date1.toISOString();
                if (col.name === 'dob') { filt[op] = dateStr; } // special case
                filt2[col.name] = filt;
                filters.push(filt2);
            } else if (col.filterOperator === '<=') {
                date1 = date;
                date1.setHours(23);
                date1.setMinutes(59);
                date1.setSeconds(59);
                filt[op] = date1.toISOString();
                if (col.name === 'dob') { filt[op] = dateStr; } // special case
                filt2[col.name] = filt;
                filters.push(filt2);
            } else if (col.filterOperator === '=') {
                date1 = new Date(date.valueOf());
                filt['>='] = date1.toISOString();
                if (col.name === 'dob') { filt['>='] = dateStr; } // special case
                filt2[col.name] = filt;
                filters.push(filt2);

                date2 = new Date(date.valueOf());
                date2.setHours(23);
                date2.setMinutes(59);
                date2.setSeconds(59);
                const filt_a: Object = {};
                const filt2_a: Object = {};
                filt_a['<='] = date2.toISOString();
                if (col.name === 'dob') { filt_a['<='] = dateStr; } // special case
                filt2_a[col.name] = filt_a;
                filters.push(filt2_a);
            } else if (col.filterOperator === '!=') {
                date1 = new Date(date.valueOf());
                filt['<'] = date1.toISOString();
                if (col.name === 'dob') { filt['<'] = dateStr; } // special case
                filt2[col.name] = filt;

                date2 = new Date(date.valueOf());
                date2.setHours(23);
                date2.setMinutes(59);
                date2.setSeconds(59);
                const filt_a: Object = {};
                const filt2_a: Object = {};
                filt_a['>'] = date2.toISOString();
                if (col.name === 'dob') { filt_a['>'] = dateStr; } // special case
                filt2_a[col.name] = filt_a;

                const date_filt: any = { '-or': [] };
                date_filt['-or'].push(filt2);
                date_filt['-or'].push(filt2_a);
                filters.push(date_filt);
            } else if (col.filterOperator === 'between') {
                date1 = date;
                date2 = this.localDateFromYmd(endDateStr);

                let date1op = '>=';
                let date2op = '<=';
                if (date1 > date2) {
                    // don't make user care about the order
                    // they enter the dates in
                    date1op = '<=';
                    date2op = '>=';
                }
                filt[date1op] = date1.toISOString();
                if (col.name === 'dob') { filt['>='] = dateStr; } // special case
                filt2[col.name] = filt;
                filters.push(filt2);

                date2.setHours(23);
                date2.setMinutes(59);
                date2.setSeconds(59);
                const filt_a: Object = {};
                const filt2_a: Object = {};
                filt_a[date2op] = date2.toISOString();
                if (col.name === 'dob') { filt_a['<='] = endDateStr; } // special case
                filt2_a[col.name] = filt_a;
                filters.push(filt2_a);
            }
            this.context.dataSource.filters[col.name] = filters;
            col.isFiltered = true;
            this.context.reload();
        }
    }
    clearDateFilter(col: GridColumn) {
        delete this.context.dataSource.filters[col.name];
        col.isFiltered = false;
        this.context.reload();
    }
    applyBooleanFilter(col: GridColumn) {
        if (!col.filterValue || col.filterValue === '') {
            delete this.context.dataSource.filters[col.name];
            col.isFiltered = false;
            this.context.reload();
        } else {
            const val: string = col.filterValue;
            const op = '=';
            const filt: Object = {};
            filt[op] = val;
            const filt2: Object = {};
            filt2[col.name] = filt;
            this.context.dataSource.filters[col.name] = [ filt2 ];
            col.isFiltered = true;
            this.context.reload();
        }
    }
    applyFilter(col: GridColumn) {
        // fallback if the operator somehow was not set yet
        if (col.filterOperator === undefined) { col.filterOperator = '='; }

        if ( (col.filterOperator !== 'null') && (col.filterOperator !== 'not null') &&
             (!col.filterValue || col.filterValue === '') &&
             (col.filterValue !== '0') ) {
            // if value is empty and we're _not_ checking for null/not null, clear
            // the filter
            delete this.context.dataSource.filters[col.name];
            col.isFiltered = false;
        } else {
            let op: string = col.filterOperator;
            let val: string = col.filterValue;
            if (col.filterOperator === 'null') {
                op  = '=';
                val = null;
            } else if (col.filterOperator === 'not null') {
                op  = '!=';
                val = null;
            } else if (col.filterOperator === 'like' || col.filterOperator === 'not like') {
                val = '%' + val + '%';
            } else if (col.filterOperator === 'startswith') {
                op = 'like';
                val = val + '%';
            } else if (col.filterOperator === 'endswith') {
                op = 'like';
                val = '%' + val;
            }
            const filt: any = {};
            if (col.filterOperator === 'not like') {
                filt['-not'] = {};
                filt['-not'][col.name] = {};
                filt['-not'][col.name]['like'] = val;
                this.context.dataSource.filters[col.name] = [ filt ];
                col.isFiltered = true;
            } else {
                filt[col.name] = {};
                filt[col.name][op] = val;
                this.context.dataSource.filters[col.name] = [ filt ];
                col.isFiltered = true;
            }
        }
        this.context.reload();
    }
    clearFilter(col: GridColumn) {
        // clear filter values...
        col.removeFilter();
        // ... and inform the data source
        delete this.context.dataSource.filters[col.name];
        col.isFiltered = false;
        this.reset();
        this.context.reload();
    }

    closeDropdown() {
        this.dropdowns.forEach(drp => { drp.close(); });
    }

    reset() {
        this.filterComboboxes.forEach(ctl => { ctl.applyEntryId(null); });
        this.dateSelects.forEach(ctl => { ctl.reset(); });
        this.orgSelects.forEach(ctl => { ctl.reset(); });
    }
}

