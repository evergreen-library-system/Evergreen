/* eslint-disable max-len */
import {Component, Input, OnInit, OnDestroy, ViewChild, ElementRef} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Subject,Observable,from,takeUntil} from 'rxjs';
import {SafeUrl} from '@angular/platform-browser';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {Pager} from '@eg/share/util/pager';
import {VolCopyContext} from './volcopy';
import {VolCopyService} from './volcopy.service';

@Component({
    selector: 'eg-volcopy-template-grid',
    templateUrl: 'template-grid.component.html'
})
export class VolCopyTemplateGridComponent implements OnInit, OnDestroy {

    private destroy$ = new Subject<void>();

    // In case we need it
    @Input() embedContext: VolCopyContext;
    context: VolCopyContext;
    loading = true;

    @ViewChild('exportLink', { static: false }) private exportLink: ElementRef;
    @ViewChild('grid', { static: true }) private grid: GridComponent;
    @ViewChild('importSummaryDialog') private importSummaryDialog: any;
    importResults: {section: string, items: string[]}[] = [];

    dataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    noSelectedRows: boolean;
    oneSelectedRow: boolean;

    constructor(
        private router: Router,
        public route: ActivatedRoute,
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private broadcaster: BroadcastService,
        private flatData: GridFlatDataService,
        public  volcopy: VolCopyService
    ) {}

    ngOnInit() {
        // console.debug('VolCopyTemplateGridComponent, ngOnInit, this', this);

        this.initDataSource();

        this.load().then( () => {
            this.grid.reload();
            this.gridSelectionChange([]); // to disable certain actions
        });

        this.volcopy.templatesRefreshed$.pipe(
            takeUntil(this.destroy$)
        ).subscribe(() => {
            // console.debug('VolCopyTemplateGridComponent, noticed templatesRefreshed$');
            setTimeout(() => { this.grid.reload(); }, 0);
        });
    }

    load(): Promise<any> {
        if (this.volcopy.currentContext) {
            this.context = this.volcopy.currentContext;
            // console.debug('VolCopyTemplateGridComponent, reusing currentContext');
            this.loading = false;
            return Promise.resolve();
        }


        this.context = new VolCopyContext();
        this.context.org = this.org; // inject;
        this.context.idl = this.idl; // inject;
        // console.debug('VolCopyTemplateGridComponent, new context');

        this.volcopy.currentContext = this.context;
        return this._load().then( () => {
            console.debug('VolCopyTemplateGridComponent, templates (and other data) fetched for VolCopyService');
        });
    }

    _load(copyIds?: number[]): Promise<any> {
        // this.sessionExpired = false;
        this.loading = true;
        this.context.reset();

        return this.volcopy.load()
            .then(result => {
                this.loading = false;
                return result;
            })
            .catch(error => {
                this.loading = false;
                console.error('VolCopyTemplateGridComponent, error loading VolCopyService', error);
                throw error;
            });
    }

    gridSelectionChange(keys: string[]) {
        this.updateSelectionState(keys);
    }

    updateSelectionState(keys: string[]) {
        this.noSelectedRows = (keys.length === 0);
        this.oneSelectedRow = (keys.length === 1);
    }

    convertTemplatesToGridRows(_templates: Record<string, any>): any[] {
        // console.debug('VolCopyTemplateGridComponent, convertTemplatesToGridRows, _templates', JSON.stringify(_templates));
        const rows: any[] = [];

        for (const [templateName, templateConfig] of Object.entries(_templates)) {
            const row: any = {
                templateName,
                location: templateConfig.location?.toString() || '',
                cost: templateConfig.cost?.toString() || '',
                fine_level: templateConfig.fine_level?.toString() || '',
                circ_as_type: templateConfig.circ_as_type || '',
                deposit: templateConfig.deposit === 't' ? $localize`Yes` : (templateConfig.deposit === 'f' ? $localize`No` : ''),
                age_protect: templateConfig.age_protect?.toString() || '',
                ref: templateConfig.ref === 't' ? $localize`Yes` : (templateConfig.ref === 'f' ? $localize`No` : ''),
                status: templateConfig.status?.toString() || '',
                circulate: templateConfig.circulate === 't' ? $localize`Yes` : (templateConfig.circulate === 'f' ? $localize`No` : ''),
                // legacy templates will give us "statcats":{"1":null,"2":null}, leading to a count of two. Do we filter?
                // I think no, because these nulls do get applied with the template. An absense of "statcats" is the correct way
                // to have the template not affect stat cats, but the legacy interface couldn't do that with stat cats.
                stat_cat_entries: templateConfig.statcats ? Object.entries( templateConfig.statcats ).length.toString() : '0',
                /* stat_cat_entries: templateConfig.statcats
                  ? Object.entries(templateConfig.statcats)
                      .filter(([_, value]) => value !== null)
                      .length
                      .toString()
                  : '0',*/
                holdable: templateConfig.holdable === 't' ? $localize`Yes` : (templateConfig.holdable === 'f' ? $localize`No` : ''),
                circ_lib: this.org.get( templateConfig.circ_lib )?.shortname() || '',
                circ_modifier: templateConfig.circ_modifier || '',
                opac_visible: templateConfig.opac_visible === 't' ? $localize`Yes` : (templateConfig.opac_visible === 'f' ? $localize`No` : ''),
                floating: templateConfig.floating?.toString() || '',
                price: templateConfig.price?.toString() || '',
                mint_condition: templateConfig.mint_condition === 't' ? $localize`Yes` : (templateConfig.mint_condition === 'f' ? $localize`No` : ''),
                deposit_amount: templateConfig.deposit_amount?.toString() || '',
                loan_duration: templateConfig.loan_duration?.toString() || '',
                copy_alerts: templateConfig.copy_alerts ? templateConfig.copy_alerts.length.toString() : '0',
                notes: templateConfig.notes ? templateConfig.notes.length.toString() : '0',
                tags: templateConfig.tags ? templateConfig.tags.length.toString() : '0',
                statcat_filter: templateConfig.statcat_filter?.toString() || '',
                owning_lib: this.org.get( templateConfig.owning_lib )?.shortname() || '',
                copy_number: templateConfig.copy_number?.toString() || '',
                label_class: templateConfig.label_class?.toString() || '',
                prefix: templateConfig.prefix?.toString() || '',
                suffix: templateConfig.suffix?.toString() || '',
                debug: JSON.stringify(templateConfig)
            };

            if (row.age_protect) {
                const rule = this.volcopy.commonData.acp_age_protect
                    .find(r => r.id() === Number(row.age_protect));
                row.age_protect = rule ? rule.name() : row.age_protect;
            }

            if (row.circ_as_type) {
                const type = this.volcopy.commonData.acp_item_type_map
                    .find(t => t.code() === row.circ_as_type);
                row.circ_as_type = type ? type.value() : row.circ_as_type;
            }

            if (row.fine_level) {
                row.fine_level = {
                    1: $localize`Low`,
                    2: $localize`Normal`,
                    3: $localize`High`
                }[row.fine_level] || row.fine_level;
            }

            if (row.floating) {
                const group = this.volcopy.commonData.acp_floating_group
                    .find(g => g.id() === Number(row.floating));
                row.floating = group ? group.name() : row.floating;
            }

            if (row.label_class) {
                const label_class = this.volcopy.commonData.acn_class
                    .find(p => p.id() === Number(row.label_class));
                row.label_class = label_class ? label_class.name() : row.label_class;
            }

            if (row.prefix) {
                const prefix = this.volcopy.commonData.acn_prefix
                    .find(p => p.id() === Number(row.prefix));
                row.prefix = prefix ? prefix.label() : row.prefix;
            }

            if (row.suffix) {
                const suffix = this.volcopy.commonData.acn_suffix
                    .find(p => p.id() === Number(row.suffix));
                row.suffix = suffix ? suffix.label() : row.suffix;
            }

            if (row.loan_duration) {
                row.loan_duration = {
                    1: $localize`Short`,
                    2: $localize`Normal`,
                    3: $localize`Long`
                }[row.loan_duration] || row.loan_duration;
            }

            if (row.location) {
                this.volcopy.getLocation(row.location).then( loc => { // delayed fleshing for the win
                    // console.debug(`Fetched location for ${row.location}:`, loc);
                    row.location = loc ?
                        `${loc.name()} (${this.org.get(loc.owning_lib()).shortname()})` :
                        `Not found, ID: ${row.location}`;
                }).catch(error => {
                    row.location = `Error with ID: ${row.location}`;
                    console.error(`Error fetching location ${row.location}:`,error);
                });
            }

            if (row.status) {
                const stat = this.volcopy.copyStatuses[row.status];
                row.status = stat ? stat.name() : row.status;
            }

            rows.push(row);
        }

        // console.debug('VolCopyTemplateGridComponent, convertTemplatesToGridRows, rows', JSON.stringify(rows));
        return rows;
    }

    initDataSource() {
        // console.debug('VolCopyTemplateGridComponent, initializing dataSource');
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            if (!this.volcopy.templates) {
                console.debug('VolCopyTemplateGridComponent, no templates available yet');
                return from([]); // Return empty array if templates aren't loaded yet
            }

            let filteredData = this.convertTemplatesToGridRows(this.volcopy.templates);

            // Apply filters
            if (Object.keys(this.dataSource.filters).length > 0) {
                filteredData = filteredData.filter(row => {
                    return Object.keys(this.dataSource.filters).every(key => {
                        const filters = this.dataSource.filters[key];

                        return filters.every(filterObj => {
                            const fieldName = Object.keys(filterObj)[0];

                            const filterDef = filterObj[fieldName];
                            const operator = Object.keys(filterDef)[0];
                            const filterValue = filterDef[operator];

                            const rowValue = row[fieldName];

                            if (fieldName === '-not') {
                                const notField = Object.keys(filterDef)[0];
                                const notOp = Object.keys(filterDef[notField])[0];
                                const notVal = filterDef[notField][notOp];
                                return !this.matchFilter(row[notField], notOp, notVal);
                            }

                            return this.matchFilter(rowValue, operator, filterValue);
                        });
                    });
                });
            }

            if (sort && sort.length > 0) {
                filteredData.sort((a, b) => {
                    for (const sortItem of sort) {
                        const dir = sortItem.dir === 'DESC' ? -1 : 1;
                        const aVal = a[sortItem.name];
                        const bVal = b[sortItem.name];

                        if (aVal < bVal) {return -1 * dir;}
                        if (aVal > bVal) {return 1 * dir;}
                    }
                    return 0;
                });
            }

            const start = pager.offset;
            const end = pager.offset + pager.limit;
            const pagedData = filteredData.slice(start, end);

            pager.resultCount = filteredData.length;

            return new Observable(subscriber => {
                pagedData.forEach(row => subscriber.next(row));
                subscriber.complete();
            });
        };
    }

    private matchFilter(value: any, operator: string, filterValue: any): boolean {
        if (value === undefined || value === null) {
            if (operator === '=' && filterValue === null) {return true;}
            if (operator === '!=' && filterValue === null) {return false;}
            return false;
        }

        switch (operator) {
            case '=':
                return filterValue === null ?
                    value === null :
                    String(value).toLowerCase() === String(filterValue).toLowerCase();
            case '!=':
                return filterValue === null ?
                    value !== null :
                    String(value).toLowerCase() !== String(filterValue).toLowerCase();
            case 'like':
                if (!filterValue) {return false;}
                return new RegExp(filterValue.replace(/%/g, '.*'), 'i').test(String(value));
            case '>':
                return Number(value) > Number(filterValue);
            case '<':
                return Number(value) < Number(filterValue);
            case '>=':
                return Number(value) >= Number(filterValue);
            case '<=':
                return Number(value) <= Number(filterValue);
            case 'in':
                return Array.isArray(filterValue) && filterValue.includes(value);
            case 'not in':
                return Array.isArray(filterValue) && !filterValue.includes(value);
            default:
                return false;
        }
    }

    exportSelected(rows?: any[]) {
        if (!rows || !rows.length) {
            rows = this.grid.context.getSelectedRows();
        }

        this.volcopy.templatesToExport = {}; // clear the old export set
        rows.forEach(t => {
            this.volcopy.templatesToExport[ t.templateName ] = this.volcopy.templates[ t.templateName ];
        });
        console.debug('Templates to export: ', this.volcopy.templatesToExport);

        if (Object.keys(this.volcopy.templatesToExport).length) {
            setTimeout(() => {
                // we need a proper click event when we pass this over to the file service
                this.exportLink.nativeElement.click();
            });
        }
    }

    exportTemplates($event = null, selected = false) {
        return this.volcopy.exportTemplate($event, selected);
    }

    importTemplates($event) {
        return this.volcopy.importTemplate($event)
            .then(result => {
                $event.target.value = ''; // reset file selection so we can re-upload if desired
                this.importResults = [];

                if (result.added.length > 0) {
                    this.importResults.push({
                        section: $localize`New Templates Added`,
                        items: result.added
                    });
                }

                if (result.overwritten.length > 0) {
                    this.importResults.push({
                        section: $localize`Existing Templates Updated`,
                        items: result.overwritten
                    });
                }

                if (this.importResults.length === 0) {
                    this.importResults.push({
                        section: $localize`Results`,
                        items: [$localize`No templates were imported`]
                    });
                }

                this.importSummaryDialog.open();
            })
            .catch(error => {
                this.importResults = [{
                    section: $localize`Error`,
                    items: [$localize`Error importing templates: ${error.message}`]
                }];
                this.importSummaryDialog.open();
            });
    }

    // Returns null when no export is in progress.
    exportTemplateUrl(): SafeUrl {
        return this.volcopy.exportTemplateUrl();
    }

    createTemplate($event) {
        console.debug('createTemplate', $event);
        const url = '/eg2/staff/cat/volcopy/template';
        window.open(url, '_blank');
    }



    editSelected(rows) {
        if (!rows.length) {
            rows = this.grid.context.getSelectedRows();
        }

        rows.forEach(t => {
            const base64Name = btoa(encodeURIComponent(t.templateName));
            const target_url = `/eg2/staff/cat/volcopy/template/${base64Name}`;
            console.debug('opening edit tab for ' + t.templateName, target_url);
            try {
                window.open(target_url, '_blank');
            } catch(E) {
                console.error('error opening edit tab for ' + t.templateName, E);
            }
        });
    }

    deleteSelected(rows) {
        if (!rows.length) { return false; }
        if (! window.confirm(
            rows.length > 1
                ? $localize`Delete selected templates?`
                : $localize`Delete selected template?`
        )) {
            return;
        }
        this.volcopy.deleteTemplates(rows.map( t => t.templateName )).then(result => {
            console.log('Deleted templates:', result.deleted);
            console.log('Templates not found:', result.notFound);
        }).catch(error => {
            console.error('Error deleting templates:', error);
        }).finally(() => {
            this.grid.reload();
        });
    }

    ngOnDestroy() {
        this.destroy$.next();
        this.destroy$.complete();
    }
}


