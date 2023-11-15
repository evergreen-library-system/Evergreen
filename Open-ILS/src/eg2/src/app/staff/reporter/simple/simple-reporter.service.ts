import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
    ActivatedRouteSnapshot} from '@angular/router';
import * as moment from 'moment-timezone';
import {Md5} from 'ts-md5';
import {EMPTY, Observable, of, from} from 'rxjs';
import {map, mergeMap, defaultIfEmpty, last} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';

const defaultFolderName = 'Simple Reporter';

const transforms = [
    {
        name: 'Bare',
        aggregate: false
    },
    {
        name: 'upper',
        aggregate: false,
        datatypes: ['text']
    },
    {
        name: 'lower',
        aggregate: false,
        datatypes: ['text']
    },
    {
        name: 'substring',
        aggregate: false,
        datatypes: ['text']
    },
    {
        name: 'day_name',
        final_datatype: 'text',
        aggregate: false,
        datatypes: ['timestamp']
    },
    {
        name: 'month_name',
        final_datatype: 'text',
        aggregate: false,
        datatypes: ['timestamp']
    },
    {
        name: 'doy',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'woy',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'moy',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'qoy',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'dom',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'dow',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'year_trunc',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'month_trunc',
        aggregate: false,
        final_datatype: 'text',
        datatypes: ['timestamp']
    },
    {
        name: 'date_trunc',
        aggregate: false,
        datatypes: ['timestamp']
    },
    {
        name: 'hour_trunc',
        aggregate: false,
        datatypes: ['timestamp']
    },
    {
        name: 'quarter',
        aggregate: false,
        datatypes: ['timestamp']
    },
    {
        name: 'months_ago',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'hod',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'quarters_ago',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'age',
        aggregate: false,
        final_datatype: 'interval',
        datatypes: ['timestamp']
    },
    {
        name: 'first',
        aggregate: true
    },
    {
        name: 'last',
        aggregate: true
    },
    {
        name: 'min',
        aggregate: true
    },
    {
        name: 'max',
        aggregate: true
    },
    // "Simple" would be to only offer the choice that's almost always what you mean.
    /* {
        name: 'count',
        aggregate: true
    },*/
    {
        name: 'count_distinct',
        final_datatype: 'number',
        aggregate: true
    },
    {
        name: 'sum',
        aggregate: true,
        datatypes: ['float', 'int', 'money', 'number']
    },
    {
        name: 'average',
        aggregate: true,
        datatypes: ['float', 'int', 'money', 'number']
    }
];

const operators = [
    {
        name: '=',
        datatypes: ['link', 'text', 'timestamp', 'interval', 'float', 'int', 'money', 'number'],
        arity: 1
    },
    {
        arity: 1,
        datatypes: ['bool', 'org_unit'],
        name: '= any'
    },
    {
        arity: 1,
        datatypes: ['bool', 'org_unit'],
        name: '<> any'
    },
    // If I had a dollar for every time someone wanted a case sensitive substring search, I might be able to buy a coffee.
    /* {
        name: 'like',
        arity: 1,
        datatypes: ['text']
    },*/
    {
        name: 'ilike',
        arity: 1,
        datatypes: ['text']
    },
    {
        name: '>',
        arity: 1,
        datatypes: ['text', 'timestamp', 'interval', 'float', 'int', 'money', 'number']
    },
    {
        name: '>=',
        arity: 1,
        datatypes: ['text', 'timestamp', 'interval', 'float', 'int', 'money', 'number']
    },
    {
        name: '<',
        arity: 1,
        datatypes: ['text', 'timestamp', 'interval', 'float', 'int', 'money', 'number']

    },
    {
        name: '<=',
        arity: 1,
        datatypes: ['text', 'timestamp', 'interval', 'float', 'int', 'money', 'number']

    },
    {
        name: 'in',
        arity: 3,
        datatypes: ['text', 'link', 'org_unit', 'float', 'int', 'money', 'number']
    },
    {
        name: 'not in',
        arity: 3,
        datatypes: ['text', 'link', 'org_unit', 'float', 'int', 'money', 'number']

    },
    {
        name: 'between',
        arity: 2,
        datatypes: ['text', 'timestamp', 'interval', 'float', 'int', 'money', 'number']

    },
    {
        name: 'not between',
        arity: 2,
        datatypes: ['text', 'timestamp', 'interval', 'float', 'int', 'money', 'number']

    },
    {
        arity: 0,
        name: 'is'
    },
    {
        arity: 0,
        name: 'is not'
    },
    {
        arity: 0,
        name: 'is blank',
        datatypes: ['text']
    },
    {
        arity: 0,
        name: 'is not blank',
        datatypes: ['text']
    }
];

const DEFAULT_TRANSFORM = 'Bare';
const DEFAULT_OPERATOR = '=';

export class SRTemplate {
    id = -1;
    rtIdl: IdlObject = null;
    name = '';
    description = ''; // description isn't currently used but someday could be
    create_time = null;
    fmClass = '';
    displayFields: IdlObject[] = [];
    orderByNames: string[] = [];
    filterFields: IdlObject[] = [];
    isNew = true;
    recurring = false;
    recurrence = null;
    excelOutput = false;
    csvOutput = true;
    htmlOutput = true;
    barCharts = false;
    lineCharts = false;
    email = '';
    runNow = 'now';
    runTime: moment.Moment = null;

    constructor(idlObj: IdlObject = null) {
        if ( idlObj !== null ) {
            this.isNew = false;
            this.id = Number(idlObj.id());
            this.create_time = idlObj.create_time();
            this.name = idlObj.name();
            this.description = idlObj.description();

            const simple_report = JSON.parse(idlObj.data()).simple_report;
            this.fmClass = simple_report.fmClass;
            this.displayFields = simple_report.displayFields;
            this.orderByNames = simple_report.orderByNames;
            this.filterFields = simple_report.filterFields;
            if (idlObj.reports()?.length) {
                const activeReport = idlObj.reports().reduce((prev, curr) =>
                    prev.create_time() > curr.create_time() ? prev : curr
                );
                if (activeReport) {
                    this.recurring = activeReport.recur() === 't';
                    this.recurrence = activeReport.recurrence();
                }
                // then fetch the most recent completed rs
                if (activeReport.runs().length) {
                    const latestSched = activeReport.runs().reduce((prev, curr) =>
                        prev.run_time() > curr.run_time() ? prev : curr
                    );
                    if (latestSched) {
                        this.excelOutput = latestSched.excel_format() === 't';
                        this.csvOutput = latestSched.csv_format() === 't';
                        this.htmlOutput = latestSched.html_format() === 't';
                        this.barCharts = latestSched.chart_bar() === 't';
                        this.lineCharts = latestSched.chart_line() === 't';
                        this.email = latestSched.email();
                        this.runTime = latestSched.run_time().length ? moment(latestSched.run_time()) : moment();
                        this.runNow = this.runTime.isAfter(moment()) ? 'later' : 'now';
                    }
                }
            }
        }
    }
}


@Injectable({
    providedIn: 'root'
})
export class SimpleReporterService {

    templateFolder: IdlObject = null;
    reportFolder: IdlObject = null;
    outputFolder: IdlObject = null;

    constructor (
        private evt: EventService,
        private auth: AuthService,
        private idl: IdlService,
        private pcrud: PcrudService
    ) {
    }

    _initFolders(): Promise<any[]> {
        if (this.templateFolder &&
            this.reportFolder &&
            this.outputFolder
        ) {
            return Promise.resolve([]);
        }

        return Promise.all([
            new Promise<void>((resolve, reject) => {
                // Verify folders exist, create if not
                this.getDefaultFolder('rtf')
                    .then(f => {
                        if (f) {
                            this.templateFolder = f;
                            resolve();
                        } else {
                            this.createDefaultFolder('rtf')
                                .then(n => {
                                    this.templateFolder = n;
                                    resolve();
                                });
                        }
                    });
            }),
            new Promise<void>((resolve, reject) => {
                this.getDefaultFolder('rrf')
                    .then(f => {
                        if (f) {
                            this.reportFolder = f;
                            resolve();
                        } else {
                            this.createDefaultFolder('rrf')
                                .then(n => {
                                    this.reportFolder = n;
                                    resolve();
                                });
                        }
                    });
            }),
            new Promise<void>((resolve, reject) => {
                this.getDefaultFolder('rof')
                    .then(f => {
                        if (f) {
                            resolve();
                            this.outputFolder = f;
                        } else {
                            this.createDefaultFolder('rof')
                                .then(n => {
                                    this.outputFolder = n;
                                    resolve();
                                });
                        }
                    });
            })
        ]);
    }

    getTransformsForDatatype(datatype: string) {
        const ret = [];
        transforms.forEach(el => {
            if ( typeof el.datatypes === 'undefined' ||
            (el.datatypes.findIndex(dt => dt === datatype) > -1) ) {
                ret.push(el);
            }
        });
        return ret;
    }

    getOperatorsForDatatype(datatype: string) {
        const ret = [];
        operators.forEach(el => {
            if ( typeof el.datatypes === 'undefined' ||
            (el.datatypes.findIndex(dt => dt === datatype) > -1) ) {
                ret.push(el);
            }
        });
        return ret;
    }

    defaultTransform() {
        return this.getTransformByName(DEFAULT_TRANSFORM);
    }

    defaultOperator(dt) {
        if (this.getOperatorByName(DEFAULT_OPERATOR).datatypes.indexOf(dt) >= 0) {
            return this.getOperatorByName(DEFAULT_OPERATOR);
        }
        return this.getOperatorsForDatatype(dt)[0];
    }

    getTransformByName(name: string) {
        return { ...transforms[transforms.findIndex(el => el.name === name)] };
    }

    getGenericTransformWithParams(ary: Array<any>) {
        const copy = Array.from(ary);
        const name = copy.shift();
        const params = [];
        const transform = { name: name, aggregate: false };

        copy.forEach(el => {
            switch (el) { // for now there's only user id for the current user, but in future ... ??
                case 'SR__USER_ID':
                    params.push(this.auth.user().id());
                    break;
                default:
                    params.push(el);
            }
        });

        if ( params.length ) {
            transform['params'] = params;
        }

        return transform;
    }

    getOperatorByName(name: string) {
        return { ...operators[operators.findIndex(el => el.name === name)] };
    }

    getDefaultFolder(fmClass: string): Promise<IdlObject> {
        return this.pcrud.search(fmClass,
            { owner: this.auth.user().id(), 'simple_reporter': 't', name: defaultFolderName },
            {}).toPromise();
    }

    createDefaultFolder(fmClass: string): Promise<IdlObject> {
        const rf = this.idl.create(fmClass);
        rf.isnew(true);
        rf.owner(this.auth.user().id());
        rf.simple_reporter(true);
        rf.name(defaultFolderName);
        return this.pcrud.create(rf).toPromise();
    }

    loadTemplate(id: number): Promise<IdlObject> {
        const searchOps = {
            flesh: 2,
            flesh_fields: {
                rt: ['reports'],
                rr: ['runs']
            }
        };
        return this.pcrud.search('rt', { id: id }, searchOps).toPromise();
    }

    saveTemplate(
        templ: SRTemplate,
        scheduleNow = false
    ): Promise<any> { // IdlObject or Number? It depends!
        const rtData = this.buildTemplateData(templ);

        // gather our parameters
        const rrData = {};
        templ.filterFields.forEach((el, idx) => {
            rrData[el.filter_placeholder] = el.force_filtervalues ? el.force_filtervalues : el.filter_value;
        });

        // Here's where we'd add rr-flags like __do_rollup to rrData

        const rtIdl = this.idl.create('rt');
        const rrIdl = this.idl.create('rr');

        if ( templ.id === -1 ) {
            rtIdl.isnew(true);
            rrIdl.isnew(true);
        } else {
            rtIdl.isnew(false);
            rrIdl.isnew(false);
            rtIdl.id(templ.id);
            rtIdl.create_time(templ.create_time);
        }
        rtIdl.name(templ.name);
        rtIdl.description(templ.description);
        rtIdl.data(JSON.stringify(rtData));
        rtIdl.owner(this.auth.user().id());
        rtIdl.folder(this.templateFolder.id());

        rrIdl.name(templ.name);
        rrIdl.data(JSON.stringify(rrData));
        rrIdl.owner(this.auth.user().id());
        rrIdl.folder(this.reportFolder.id());
        rrIdl.template(templ.id);
        rrIdl.create_time('now'); // rr create time is serving as the edit time
        // of the SR template as a whole

        rrIdl.recur(templ.recurring ? 't' : 'f');
        rrIdl.recurrence(templ.recurrence);

        return this.pcrud.search('rt', { name: rtIdl.name(), folder: rtIdl.folder() })
            .pipe(defaultIfEmpty(rtIdl), map(existing => {
                if (existing.id() !== rtIdl.id()) { // oh no! dup name
                    throw new Error(': Duplicate Report Name');
                }

                if ( templ.id === -1 ) {
                    return this.pcrud.create(rtIdl).pipe(mergeMap(rt => {
                        rrIdl.template(rt.id());
                        // after saving the rr, return an Observable of the rt
                        // to the caller
                        return this.pcrud.create(rrIdl).pipe(mergeMap(
                            rr => this.scheduleReport(templ, rr, scheduleNow).pipe(mergeMap(rs => of(rt)))
                        ));
                    })).toPromise();
                } else {
                    const emptyRR = this.idl.create('rr');
                    emptyRR.id('no_rr');
                    return this.pcrud.update(rtIdl).pipe(mergeMap(rtId => {
                    // we may or may not have the rr already created, so
                    // test and act accordingly
                        return this.pcrud.search('rr', { template: rtId }).pipe(defaultIfEmpty(emptyRR), mergeMap(rr => {
                            if (rr.id() === 'no_rr') {
                                rrIdl.isnew(true);
                                return this.pcrud.create(rrIdl).pipe(mergeMap(rr2 =>
                                    this.scheduleReport(templ, rr2, scheduleNow).pipe(mergeMap(rs => of(rtId)))
                                ));
                            } else {
                                rr.create_time('now'); // rr create time is serving as the
                                // edit time of the SR template as a whole
                                rr.recur(templ.recurring ? 't' : 'f');
                                rr.recurrence(templ.recurrence);
                                rr.data(rrIdl.data());
                                return this.pcrud.update(rr).pipe(mergeMap(
                                    rr2 => this.scheduleReport(templ, rr, scheduleNow).pipe(mergeMap(rs => of(rtId) ))
                                ));
                            }
                        }));
                    })).toPromise();
                }
            })).toPromise();
    }

    scheduleReport(templ: SRTemplate, rr: IdlObject, scheduleNow: boolean): Observable<IdlObject> {
        const rs = this.idl.create('rs');
        if (!scheduleNow) {
            return of(rs); // return a placeholder
        }
        rs.isnew(true);
        rs.report(rr.id());
        rs.folder(this.outputFolder.id());
        rs.runner(rr.owner());
        if (templ.runNow === 'now') {
            rs.run_time('now');
        } else {
            rs.run_time(templ.runTime.toISOString());
        }
        rs.email(templ.email);
        rs.excel_format(templ.excelOutput ? 't' : 'f');
        rs.csv_format(templ.csvOutput ? 't' : 'f');
        rs.html_format(templ.htmlOutput ? 't' : 'f');
        rs.chart_line(templ.lineCharts ? 't' : 'f');
        rs.chart_bar(templ.barCharts ? 't' : 'f');
        rs.isnew(true);

        // clear any un-run schedules, then add the new one
        const emptyRS = this.idl.create('rs');
        emptyRS.id('no_rs');
        return this.pcrud.search('rs', { report: rr.id(), start_time: {'=' : null} }, {}, {atomic: true}).pipe(mergeMap(old_rs => {
            if (old_rs.length > 0) {
                old_rs.forEach(x => x.isdeleted(true));
                old_rs.push(rs);
                return this.pcrud.autoApply(old_rs).pipe(last()); // note that we don't care
                // what the last one processed
                // actually is
            } else {
                return this.pcrud.create(rs);
            }
        }));
    }

    // The template generated by this can obviously be trimmed to only those things
    // that SQLBuilder.pm cares about, but for now it's basically the same as the
    // existing template builder.
    buildTemplateData(
        templ: SRTemplate
    ) {
        const fmClass = templ.fmClass;
        const sourceClass = this.idl.classes[fmClass];
        const md5Name = Md5.hashStr(fmClass); // Just the one with SR since there are no joins
        let conditionCount = 0;

        // The simplified template that can be edited and re-saved
        const simpleReport = {
            name: templ.name,
            fmClass: fmClass,
            displayFields: templ.displayFields,
            orderByNames: templ.orderByNames,
            filterFields: templ.filterFields,
        };
        const reportTemplate = {
            simple_report: simpleReport,
            version: 5,
            core_class: fmClass,
            'from': {
                alias: md5Name,
                path: fmClass + '-' + fmClass,
                table: sourceClass.source,
                idlclass: fmClass,
                label: sourceClass.label
            },
            select: [],
            where: [],
            having: [],
            order_by: []
        };
        // fill in select[] and display_cols[] simultaneously
        templ.displayFields.forEach((el, idx) => {
            reportTemplate.select.push({
                alias: el.alias,
                path: fmClass + '-' + el.name,
                relation: md5Name,
                column: {
                    colname: el.name,
                    transform: el.transform.name,
                    aggregate: el.transform.aggregate
                }
            });

        }); // select[]

        // where[] and having[] are the same save for aggregate == true
        templ.filterFields.forEach((el, idx) => {
            let whereObj = {};

            whereObj = {
                alias: el.alias,
                path: fmClass + '-' + el.name,
                relation: md5Name,
                column: {
                    colname: el.name,
                    transform: el.transform.name,
                    aggregate: el.transform.aggregate
                },
                condition: {}
            };

            // No test for el.filterValue because currently all filter values are assigned at schedule time
            whereObj['condition'][el.operator.name] = '::P' + conditionCount;
            el.filter_placeholder = 'P' + conditionCount;
            conditionCount++;

            // handle force transforms
            if (el.force_transform) {
                whereObj['column']['params'] = el.transform.params;
            }

            if ( el.transform.aggregate ) {
                reportTemplate.having.push(whereObj);
            } else {
                reportTemplate.where.push(whereObj);
            }

        }); // where[] and having[]

        templ.orderByNames.forEach(ob => { // order_by and select have the same shape
            const el = templ.displayFields[templ.displayFields.findIndex(fl => fl.name === ob)];
            reportTemplate.order_by.push({
                alias: el.alias,
                path: fmClass + '-' + el.name,
                relation: md5Name,
                direction: el.direction ? el.direction : 'ascending',
                column: {
                    colname: el.name,
                    transform: el.transform.name,
                    aggregate: el.transform.aggregate
                }
            });
        });

        return reportTemplate;
    }

    getOutputDatasource() {
        const gridSource = new GridDataSource();

        gridSource.sort = [{ name: 'complete_time', dir: 'DESC' }];

        gridSource.getRows = (pager: Pager, sort: any[]) => {

            // start setting up query
            const base: Object = {};
            base['runner'] = this.auth.user().id();
            base['output_folder'] = this.outputFolder.id();
            const query: any = new Array();
            query.push(base);

            // and add any filters
            Object.keys(gridSource.filters).forEach(key => {
                Object.keys(gridSource.filters[key]).forEach(key2 => {
                    query.push(gridSource.filters[key][key2]);
                });
            });

            const orderBy: any = {};
            if (sort.length) {
                orderBy.rcr = sort[0].name + ' ' + sort[0].dir;
            }

            const searchOpts = {
                flesh: 2,
                flesh_fields: {
                    rcr: ['run'],
                },
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            return this.pcrud.search('rcr', query, searchOpts)
                .pipe(map(row => {
                    if ( this.evt.parse(row) ) {
                        throw new Error(row);
                    } else {
                        return {
                            template_name: row.template_name(),
                            complete_time: row.complete_time(),
                            id: row.run().id(),
                            report_id: row.report(),
                            template_id: row.template(),
                            error_code: row.run().error_code(),
                            error_text: row.run().error_text(),
                            _rs: row.run()
                        };
                    }
                }));

        };

        return gridSource;
    }

    getReportsDatasource() {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) {
                orderBy.rt = sort[0].name + ' ' + sort[0].dir;
            } else {
                orderBy.rt = 'create_time desc';
            }

            // start setting up query
            const base: Object = {};
            base['owner'] = this.auth.user().id();
            base['folder'] = this.templateFolder.id();

            const query: any = new Array();
            query.push(base);

            // and add any filters
            Object.keys(gridSource.filters).forEach(key => {
                Object.keys(gridSource.filters[key]).forEach(key2 => {
                    query.push(gridSource.filters[key][key2]);
                });
            });

            const searchOps = {
                flesh: 2,
                flesh_fields: {
                    rt: ['reports'],
                    rr: ['runs']
                },
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            return this.pcrud.search('rt', query, searchOps).pipe(map(row => {
                let edit_time = null;
                let last_run = null;
                let past = [];
                let future = [];
                let next_run = null;
                let recurring = false;

                // there should be exactly one rr associated with the template,
                // but in case not, we'll just pick the one with the most
                // recent create time
                if (row.reports().length) {
                    const activeReport = row.reports().reduce((prev, curr) =>
                        prev.create_time() > curr.create_time() ? prev : curr
                    );
                    if (activeReport) {
                        // note that we're (ab)using the rr create_time
                        // to be the edit time of the SR rt + rr combo
                        edit_time = activeReport.create_time();
                        recurring = activeReport.recur() === 't';
                    }
                    // then fetch the most recent completed rs
                    if (activeReport.runs().length) {
                        let lastRun = null;
                        past = activeReport.runs().filter(el => el.start_time() !== null);
                        if (past.length) {
                            lastRun = past.reduce((prev, curr) =>
                                prev.complete_time() > curr.complete_time() ? prev : curr
                            );
                        }
                        if (lastRun) {
                            last_run = lastRun.complete_time();
                        }

                        // And the next rs not yet in progress
                        let nextRun = null;
                        future = activeReport.runs().filter(el => el.start_time() === null);
                        if (future.length) {
                            nextRun = future.reduce((prev, curr) =>
                                prev.run_time() < curr.run_time() ? prev : curr
                            );
                        }
                        if (nextRun) {
                            next_run = nextRun.run_time();
                        }
                    }
                }
                return {
                    name: row.name(),
                    rt_id: row.id(),
                    create_time: row.create_time(),
                    edit_time: edit_time,
                    last_run: last_run,
                    next_run: next_run,
                    recurring: recurring,
                };
            }));
        };

        return gridSource;
    }
}

@Injectable()
export class SimpleReporterServiceResolver implements Resolve<Promise<any[]>> {

    constructor(
                private router: Router,
                private perm: PermService,
                private svc: SimpleReporterService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        return from(this.perm.hasWorkPermHere('RUN_SIMPLE_REPORTS')).pipe(mergeMap(
            permResult => {
                if (permResult['RUN_SIMPLE_REPORTS']) {
                    return Promise.all([
                        this.svc._initFolders()
                    ]);
                } else {
                    this.router.navigate(['/staff/no_permission']);
                    return EMPTY;
                }
            }
        )).toPromise();
    }

}
