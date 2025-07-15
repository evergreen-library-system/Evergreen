/* eslint-disable */
import {Injectable} from '@angular/core';
import {Router, Resolve, RouterStateSnapshot,
    ActivatedRouteSnapshot} from '@angular/router';
import * as moment from 'moment-timezone';
import {Md5} from 'ts-md5';
import {map, switchMap, mergeMap, concatMap, defaultIfEmpty, last} from 'rxjs/operators';
import {EMPTY, Observable, of, from} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {Tree, TreeNode} from '@eg/share/tree/tree';

const defaultSRFolderName = 'Simple Reporter';

const OILS_RPT_DTYPE_ARRAY = 'array';
const OILS_RPT_DTYPE_STRING = 'text';
const OILS_RPT_DTYPE_MONEY = 'money';
const OILS_RPT_DTYPE_BOOL = 'bool';
const OILS_RPT_DTYPE_INT = 'int';
const OILS_RPT_DTYPE_ID = 'id';
const OILS_RPT_DTYPE_OU = 'org_unit';
const OILS_RPT_DTYPE_FLOAT = 'float';
const OILS_RPT_DTYPE_TIMESTAMP = 'timestamp';
const OILS_RPT_DTYPE_INTERVAL = 'interval';
const OILS_RPT_DTYPE_LINK = 'link';
const OILS_RPT_DTYPE_NONE = '';
const OILS_RPT_DTYPE_NULL = null;

const OILS_RPT_DTYPE_ALL = [
    OILS_RPT_DTYPE_STRING,
    OILS_RPT_DTYPE_MONEY,
    OILS_RPT_DTYPE_INT,
    OILS_RPT_DTYPE_ID,
    OILS_RPT_DTYPE_FLOAT,
    OILS_RPT_DTYPE_TIMESTAMP,
    OILS_RPT_DTYPE_BOOL,
    OILS_RPT_DTYPE_OU,
    OILS_RPT_DTYPE_NONE,
    OILS_RPT_DTYPE_NULL,
    OILS_RPT_DTYPE_INTERVAL,
    OILS_RPT_DTYPE_LINK
];
const OILS_RPT_DTYPE_NOT_ID =   [OILS_RPT_DTYPE_STRING,OILS_RPT_DTYPE_MONEY,OILS_RPT_DTYPE_INT,OILS_RPT_DTYPE_FLOAT,OILS_RPT_DTYPE_TIMESTAMP];
const OILS_RPT_DTYPE_NOT_BOOL = [OILS_RPT_DTYPE_STRING,OILS_RPT_DTYPE_MONEY,OILS_RPT_DTYPE_INT,OILS_RPT_DTYPE_FLOAT,OILS_RPT_DTYPE_TIMESTAMP,OILS_RPT_DTYPE_ID,OILS_RPT_DTYPE_OU,OILS_RPT_DTYPE_LINK];


const transforms = [
    {
        name: 'Bare',
        simple: true,
        aggregate: false
    },
    {
        name: 'upper',
        simple: true,
        aggregate: false,
        datatypes: ['text']
    },
    {
        name: 'first5',
        simple: false,
        aggregate: false,
        datatypes: ['text']
    },
    {
        name: 'lower',
        simple: true,
        aggregate: false,
        datatypes: ['text']
    },
    {
        name: 'substring',
        simple: true,
        aggregate: false,
        datatypes: ['text']
    },
    {
        name: 'day_name',
        simple: true,
        final_datatype: 'text',
        aggregate: false,
        datatypes: ['timestamp']
    },
    {
        name: 'month_name',
        simple: true,
        final_datatype: 'text',
        aggregate: false,
        datatypes: ['timestamp']
    },
    {
        name: 'doy',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'woy',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'moy',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'qoy',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'dom',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'dow',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'year_trunc',
        simple: true,
        relative_time_input_transform: 'relative_year',
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp'],
        regex : /^\d{4}$/,
        hint  : 'YYYY',
        cal_format : '%Y',
        input_size : 4
    },
    {
        name: 'month_trunc',
        simple: true,
        relative_time_input_transform: 'relative_month',
        aggregate: false,
        final_datatype: 'text',
        datatypes: ['timestamp'],
        regex : /^\d{4}-\d{2}$/,
        hint  : 'YYYY-MM',
        cal_format : '%Y-%m',
        input_size : 7
    },
    {
        name: 'date_trunc',
        simple: true,
        relative_time_input_transform: 'relative_date',
        aggregate: false,
        final_datatype: 'timestamp',
        datatypes: ['timestamp'],
        regex : /^\d{4}-\d{2}-\d{2}$/,
        hint  : 'YYYY-MM-DD',
        cal_format : '%Y-%m-%d',
        input_size : 10

    },
    {
        name: 'date', // old templates use this
        hidden: true,
        simple: true,
        relative_time_input_transform: 'relative_date',
        aggregate: false,
        final_datatype: 'timestamp',
        datatypes: ['timestamp'],
        regex : /^\d{4}-\d{2}-\d{2}$/,
        hint  : 'YYYY-MM-DD',
        cal_format : '%Y-%m-%d',
        input_size : 10

    },
    {
        name: 'hour_trunc',
        simple: true,
        aggregate: false,
        final_datatype: 'text',
        datatypes: ['timestamp'],
        regex : /^\d{2}$/,
        hint  : 'HH',
        cal_format : '%Y-%m-$d %H',
        input_size : 2
    },
    {
        name: 'quarter',
        simple: true,
        aggregate: false,
        final_datatype: 'text',
        datatypes: ['timestamp'],
        regex : /^\d{4}-Q\d{1}$/,
        hint  : 'YYYY-Qx',
        cal_format : '%Y-%Q',
        input_size : 7
    },
    {
        name: 'months_ago',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'hod',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp'],
        cal_format : '%H',
        regex : /^\d{1,2}$/

    },
    {
        name: 'quarters_ago',
        simple: true,
        aggregate: false,
        final_datatype: 'number',
        datatypes: ['timestamp']
    },
    {
        name: 'age',
        simple: true,
        aggregate: false,
        final_datatype: 'interval',
        datatypes: ['timestamp']
    },
    {
        name: 'first',
        simple: true,
        aggregate: true
    },
    {
        name: 'last',
        simple: true,
        aggregate: true
    },
    {
        name: 'min',
        simple: true,
        aggregate: true
    },
    {
        name: 'max',
        simple: true,
        aggregate: true
    },
    {
        name: 'count',
        simple: true,
        hidden: true,
        final_datatype: 'number',
        aggregate: true
    },
    {
        name: 'count_distinct',
        simple: true,
        final_datatype: 'number',
        aggregate: true
    },
    {
        name: 'sum',
        simple: true,
        aggregate: true,
        datatypes: ['float', 'int', 'money', 'number']
    },
    {
        name: 'average',
        simple: true,
        aggregate: true,
        datatypes: ['float', 'int', 'money', 'number']
    },
    {
        name: 'round',
        simple: false,
        aggregate: false,
        datatypes: ['float', 'int', 'number']
    }
];

const operators = [
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
    {
        name: '=',
        datatypes: ['link', 'text', 'timestamp', 'interval', 'float', 'int', 'money', 'number', 'id', 'bool', 'org_unit'],
        hidden: ['bool', 'org_unit'], // This is here to support old templates that don't know how to use the newer bool/org operators
        arity: 1
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
        datatypes: ['text', 'link', 'org_unit', 'float', 'int', 'money', 'number', 'id']
    },
    {
        name: 'not in',
        arity: 3,
        datatypes: ['text', 'link', 'org_unit', 'float', 'int', 'money', 'number', 'id']

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
    rrIdl: IdlObject = null;
    name = '';
    doc_url = '';
    description = ''; // description isn't currently used but someday could be
    templateFormatVersion = null;
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
    newRecordBucket = false;
    existingRecordBucket = false;
    email = '';
    pivotLabel = '';
    pivotData = 0;
    recordBucket = null;
    bibColumnNumber = '';
    doRollup = false;
    runNow = 'now';
    runTime: moment.Moment = null;

    aggregateDisplayFields() {
        return this.displayFields.filter(f => f.transform.aggregate);
    }

    nonAggregateDisplayFields() {
        return this.displayFields.filter(f => !f.transform.aggregate);
    }

    findFilterfieldByPlaceholder (ph) {
        return this.filterFields.filter(f => f.filter_placeholder === ph)[0];
    }

    constructor(idlObj: IdlObject = null, templateOnly = false) {
        if ( idlObj !== null ) {
            this.isNew = false;
            this.id = Number(idlObj.id());
            this.create_time = idlObj.create_time();
            this.name = idlObj.name();
            this.description = idlObj.description();

            const rtData = JSON.parse(idlObj.data());
            this.doc_url = rtData.doc_url;
            this.templateFormatVersion = rtData.version;

            const simple_report = rtData.simple_report;
            this.fmClass = simple_report.fmClass;
            this.displayFields = simple_report.displayFields;
            this.orderByNames = simple_report.orderByNames;
            this.filterFields = simple_report.filterFields;
            if (!templateOnly && idlObj.reports()?.length) {
                const activeReport = idlObj.reports().reduce((prev, curr) =>
                    prev.create_time() > curr.create_time() ? prev : curr
                );
                if (activeReport) {
                    this.recurring = activeReport.recur() === 't';
                    this.recurrence = activeReport.recurrence();

                    const arData = JSON.parse(activeReport.data());
                    Object.keys(arData).forEach(maybePlaceholder => {
                        const ffield = this.findFilterfieldByPlaceholder(maybePlaceholder);
                        if (ffield) {
                            ffield.filter_value = arData[maybePlaceholder];
                            if (ffield.filter_value) {
                                if (Array.isArray(ffield.filter_value)) {
                                    if (ffield.filter_value[0]?.transform?.match(/^relative_/).length > 0) {
                                        ffield.transform.relativeTransform = true;
                                    }
                                } else if (typeof ffield.filter_value === 'object') {
                                    ffield._org_family_primaryOrgId = ffield.filter_value._org_family_primaryOrgId;
                                    ffield._org_family_includeAncestors = ffield.filter_value._org_family_includeAncestors;
                                    ffield._org_family_includeDescendants = ffield.filter_value._org_family_includeDescendants;
                                    ffield.transform.relativeTransform = !!(ffield.filter_value.transform?.match(/^relative_/)?.length > 0);
                                }
                            }
                        }
                    });
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
export class ReporterService {

    currentFolderType = '';
    selectedTemplate: IdlObject = null;
    selectedReport: IdlObject = null;

    lastNewFolderName = '';
    templateFolderList: IdlObject[] = [];
    reportFolderList: IdlObject[] = [];
    outputFolderList: IdlObject[] = [];

    myFolderTrees = { templates: null, reports: null, outputs: null };
    sharedFolderTrees = { templates: null, reports: null, outputs: null };

    templateSearchFolderTree: Tree = null;

    templateFolder: IdlObject = null;
    reportFolder: IdlObject = null;
    outputFolder: IdlObject = null;

    globalCanShare: boolean = false;
    topPermOrg = { RUN_REPORTS: -1, SHARE_REPORT_FOLDER: -1, VIEW_REPORT_OUTPUT: -1 };

    constructor (
        private evt: EventService,
        private auth: AuthService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private org: OrgService,
        private net: NetService
    ) {
        this.reloadFolders();
    }

    canDeleteFolder(fldr, gridDS) {
        return !this.folderListByType(fldr.classname).find(f => f.parent() == fldr.id())
                && gridDS.data.length === 0;
    }

    deleteFolder(fldr) {

        let type = fldr.classname;
        if (type === 'rtf') {
            type = 'template';
        }
        if (type === 'rrf') {
            type = 'report';
        }
        if (type === 'rof') {
            type = 'output';
        }

        return this.net.request(
            'open-ils.reporter',
            'open-ils.reporter.folder.delete',
            this.auth.token(), type, fldr.id()
        ).pipe(map(res => {
            if ( this.evt.parse(res) ) {
                throw new Error(res);
            }
            return res;
        })).subscribe(
            f => {},
            (e: unknown) => { alert('ah!' + e); },
            () => this.reloadFolders()
        );
    }

    folderListByType(type) {
        if (type === 'rtf') {
            return this.templateFolderList;
        }
        if (type === 'rrf') {
            return this.reportFolderList;
        }
        if (type === 'rof') {
            return this.outputFolderList;
        }
    }

    folderByTypeAndId(type,id) {
        return this.folderListByType(type).find(f => f.id() == id);
    }

    folderIsMine(f: IdlObject): boolean {
        return !!(f.owner().id() == this.auth.user().id());
    }

    renameReportFolder(new_name) {
        return this.renameFolder(new_name, this.reportFolder);
    }

    renameTemplateFolder(new_name) {
        return this.renameFolder(new_name, this.templateFolder);
    }

    renameOutputFolder(new_name) {
        return this.renameFolder(new_name, this.outputFolder);
    }

    renameFolder(new_name, fldr) {
        if (fldr && new_name) {
            fldr.name(new_name);
            return this.pcrud.update(fldr)
                .subscribe(
                    f => {},
                    (e: unknown) => { alert('ah!' + e); },
                    () => this.reloadFolders()
                );
        }
        return of(fldr);
    }

    shareFolder(fldr, org) {
        if (fldr && org) {
            fldr.share_with(this.org.get(org).id());
            fldr.shared('t');
            return this.pcrud.update(fldr)
                .subscribe(
                    f => {},
                    (e: unknown) => { alert('ah!' + e); },
                    () => this.reloadFolders()
                );
        }
        return of(fldr);
    }

    unshareFolder(fldr) {
        if (fldr) {
            fldr.shared('f');
            return this.pcrud.update(fldr)
                .subscribe(
                    f => {},
                    (e: unknown) => { alert('ah!' + e); },
                    () => this.reloadFolders()
                );
        }
        return of(fldr);
    }

    updateContainingFolder(obj_list: IdlObject[], fldr: IdlObject) {
        console.log('before fetch and change:',obj_list);
        return this.pcrud.search(
            obj_list[0].classname,
            {id : { in : obj_list.map(o => o.id()) }},
            {}, {atomic: true}
        ).pipe(mergeMap(fresh_objs => {
            fresh_objs.forEach(o => {
    	    	o.folder(fldr.id());
            });
            console.log('after fetch and change:',fresh_objs);
		    return this.pcrud.update(fresh_objs).pipe(last());
        }));

    }

    newSubfolder(new_name, fldr: IdlObject) {
        if (new_name) {
            const new_folder = this.idl.create(fldr.classname);
            new_folder.isnew(true);
            new_folder.name(new_name);
            new_folder.owner(this.auth.user().id());
            if (fldr) {
                new_folder.parent(fldr.id());
            }
            return this.pcrud.create(new_folder).subscribe(
                f => this.lastNewFolderName = new_name,
                (e: unknown) => { alert('ah!' + e); },
                () => this.reloadFolders()
            );
        }
        return of();
    }

    newTypedFolder(new_name, ftype) {
        if (new_name) {
            const new_folder = this.idl.create(ftype);
            new_folder.isnew(true);
            new_folder.name(new_name);
            new_folder.owner(this.auth.user().id());
            return this.pcrud.create(new_folder).subscribe(
                f => this.lastNewFolderName = new_name,
                (e: unknown) => { alert('ah!' + e); },
                () => this.reloadFolders()
            );
        }
        return of();
    }

    newOutputFolder(new_name, fldr?: IdlObject) {
        return this.newTypedFolder(new_name, fldr?.classname || 'rof');
    }

    newReportFolder(new_name, fldr?: IdlObject) {
        return this.newTypedFolder(new_name, fldr?.classname || 'rrf');
    }

    newTemplateFolder(new_name, fldr?: IdlObject) {
        return this.newTypedFolder(new_name, fldr?.classname || 'rtf');
    }

    reloadFolders(): Promise<any[]> {

        this.templateSearchFolderTree = new Tree(new TreeNode({
	    	id: 'my-templates',
		    label: $localize`All Folders`,
            children: [],
		    callerData: {}
        }));

        this.myFolderTrees = {
            templates: new Tree(new TreeNode({
    	    	id: 'my-templates',
			    label: $localize`Templates`,
                stateFlag: true,
                expanded: false,
                children: [],
			    callerData: { type: 'rtf' }
            })),

            reports: new Tree(new TreeNode({
    	    	id: 'my-reports',
			    label: $localize`Reports`,
                stateFlag: true,
                expanded: false,
                children: [],
			    callerData: { type: 'rrf' }
            })),

            outputs: new Tree(new TreeNode({
    	    	id: 'my-outputs',
			    label: $localize`Outputs`,
                stateFlag: true,
                expanded: false,
                children: [],
			    callerData: { type: 'rof' }
            }))
        };

        this.sharedFolderTrees = {
            templates: new Tree(new TreeNode({
        		id: 'shared-templates',
		    	label: $localize`Templates`,
                stateFlag: false,
                expanded: false,
                children: [],
			    callerData: { type: 'rtf' }
            })),

            reports: new Tree(new TreeNode({
    	    	id: 'shared-reports',
			    label: $localize`Reports`,
                stateFlag: false,
                expanded: false,
                children: [],
			    callerData: { type: 'rrf' }
            })),

            outputs: new Tree(new TreeNode({
    	    	id: 'shared-outputs',
			    label: $localize`Outputs`,
                stateFlag: false,
                expanded: false,
                children: [],
			    callerData: { type: 'rof' }
            }))
        };

        const perm_list = [ 'RUN_REPORTS', 'SHARE_REPORT_FOLDER', 'VIEW_REPORT_OUTPUT' ];
        return Promise.all([
            new Promise<void>((resolve, reject) => {
                this.net.request(
                    'open-ils.actor',
                    'open-ils.actor.user.perm.highest_org.batch',
                    this.auth.token(), this.auth.user().id(), perm_list
                ).toPromise()
                .then(permset => {
                    permset.forEach((perm_org,ind) => this.topPermOrg[perm_list[ind]] = perm_org);
                    if (this.topPermOrg.SHARE_REPORT_FOLDER > -1) this.globalCanShare = true;
                    resolve();
                });
            }),
            new Promise<void>((resolve, reject) => {
                this.net.request(
                    'open-ils.reporter',
                    'open-ils.reporter.folder.visible.retrieve',
                    this.auth.token(),
                    'template').toPromise()
                    .then(fldrs => {

                        this.treeifyFolders(this.templateSearchFolderTree, fldrs, false);
                        resolve();
                    });
            }),
            new Promise<void>((resolve, reject) => {
                this.net.request(
                    'open-ils.reporter',
                    'open-ils.reporter.folder.visible.retrieve',
                    this.auth.token(),
                    'template').toPromise()
                    .then(fldrs => {
                        this.templateFolderList = fldrs;
                        const mine = fldrs.filter(f => f.owner().id() == this.auth.user().id());
                        const shared = fldrs.filter(f => f.owner().id() != this.auth.user().id());

                        this.treeifyFolders(this.myFolderTrees.templates, mine, true);
                        this.treeifyFolders(this.sharedFolderTrees.templates, shared, false);

                        resolve();
                    });
            }),
            new Promise<void>((resolve, reject) => {
                this.net.request(
                    'open-ils.reporter',
                    'open-ils.reporter.folder.visible.retrieve',
                    this.auth.token(),
                    'report').toPromise()
                    .then(fldrs => {
                        this.reportFolderList = fldrs;
                        const mine = fldrs.filter(f => f.owner().id() == this.auth.user().id());
                        const shared = fldrs.filter(f => f.owner().id() != this.auth.user().id());

                        this.treeifyFolders(this.myFolderTrees.reports, mine, true);
                        this.treeifyFolders(this.sharedFolderTrees.reports, shared, false);

                        resolve();
                    });
            }),
            new Promise<void>((resolve, reject) => {
                this.net.request(
                    'open-ils.reporter',
                    'open-ils.reporter.folder.visible.retrieve',
                    this.auth.token(),
                    'output').toPromise()
                    .then(fldrs => {
                        this.outputFolderList = fldrs;
                        const mine = fldrs.filter(f => f.owner().id() == this.auth.user().id());
                        const shared = fldrs.filter(f => f.owner().id() != this.auth.user().id());

                        this.treeifyFolders(this.myFolderTrees.outputs, mine, true);
                        this.treeifyFolders(this.sharedFolderTrees.outputs, shared, false);

                        resolve();
                    });
            })
        ]);

    }

    tempFolderTree (tree_type, mine = true, shared = false, expanded = false) {
        let flist = [];
        let label = '';
        switch (tree_type) {
            case 'rtf':
                flist = this.templateFolderList;
                label = $localize`Templates`;
                break;
            case 'rrf':
                flist = this.reportFolderList;
                label = $localize`Reports`;
                break;
            case 'rof':
                flist = this.outputFolderList;
                label = $localize`Folders`;
                break;
            default:
                break;
        }

        const mine_list = flist.filter(f => f.owner().id() == this.auth.user().id());
        const shared_list = flist.filter(f => f.owner().id() != this.auth.user().id());

        flist = [];

        if (mine) {flist = flist.concat(mine_list);}
        if (shared) {flist = flist.concat(shared_list);}

        const temp_tree = new Tree(new TreeNode({
	    	id: 'temp-tree',
		    label: label,
            children: [],
		    callerData: {}
        }));

        this.treeifyFolders(temp_tree, flist, false);
        if (expanded) {temp_tree.expandAll();}
        return temp_tree;
    }

    treeifyFolders (tree, folders, state) {
        while (folders.length) {
            const f = folders.shift();

            let current_root = tree.rootNode;

            let sharedLabel = '';
            if (f.shared() === 't' && f.share_with()) {
                sharedLabel = ' (' + this.org.get(f.share_with()).shortname() + ')';
                if ( f.owner().id() != this.auth.user().id() ) { // shared with me, not by me
                    const shared_folder_id = 'shared-by-' + f.owner().id();
                    current_root = tree.findNode(shared_folder_id);
                    if (!current_root) {
                        current_root = new TreeNode({
                            id: shared_folder_id,
                            label: f.owner().usrname(),
                            expanded: false,
                            stateFlag: false,
                            children: [],
                            callerData: { type: tree.rootNode.callerData.type }
                        });
                        tree.rootNode.children.push( current_root );
                        tree.rootNode.children.sort((a,b) => a.label.localeCompare(b.label) );
                    }

                }
            }

            if (f.parent()) { // not a top folder
                const p = tree.findNode(f.parent());
                if (!p) {
                    // if the parent is NOT somewhere in the list waiting to be inserted...
                    if (folders.filter(x => x.id() == f.parent()).length == 0) {
                        // .. just make it parentless, it's a shared folder but we don't have the parent shared
                        f.parent(null);
                    }
                    folders.push(f);
                } else {
                    p.children.push(new TreeNode({
                        id: f.id(),
                        label: f.name() + sharedLabel,
                        expanded: false,
                        stateFlag: state,
                        callerData: {
                            folderIdl: f
                        }
                    }));
                }
            } else { // no parent defined, add to the root's kids
                current_root.children.push(new TreeNode({
                    id: f.id(),
                    label: f.name() + sharedLabel,
                    expanded: false,
                    stateFlag: state,
                    callerData: {
                        folderIdl: f
                    }
                }));
            }
        }
    }

    _initSRFolders(): Promise<any[]> {
        if (this.templateFolder &&
            this.reportFolder &&
            this.outputFolder
        ) {
            return Promise.resolve([]);
        }

        return Promise.all([
            new Promise<void>((resolve, reject) => {
                // Verify folders exist, create if not
                this.getDefaultSRFolder('rtf')
                    .then(f => {
                        if (f) {
                            this.templateFolder = f;
                            resolve();
                        } else {
                            this.createDefaultSRFolder('rtf')
                                .then(n => {
                                    this.templateFolder = n;
                                    resolve();
                                });
                        }
                    });
            }),
            new Promise<void>((resolve, reject) => {
                this.getDefaultSRFolder('rrf')
                    .then(f => {
                        if (f) {
                            this.reportFolder = f;
                            resolve();
                        } else {
                            this.createDefaultSRFolder('rrf')
                                .then(n => {
                                    this.reportFolder = n;
                                    resolve();
                                });
                        }
                    });
            }),
            new Promise<void>((resolve, reject) => {
                this.getDefaultSRFolder('rof')
                    .then(f => {
                        if (f) {
                            resolve();
                            this.outputFolder = f;
                        } else {
                            this.createDefaultSRFolder('rof')
                                .then(n => {
                                    this.outputFolder = n;
                                    resolve();
                                });
                        }
                    });
            })
        ]);
    }

    getCoreSources () {
        const ret = [];
        Object.values(this.idl.classes).forEach(c => {
            if (c && typeof c['core'] !== 'undefined' && c['core']) {
                if (typeof c['label'] === 'undefined') {c['label'] = c['name'];}
                ret.push(c);
            }
        });
        return ret.sort( (a,b) => a.label.localeCompare(b.label) );
    }

    getNonCoreSources () {
        const ret = [];
        Object.values(this.idl.classes).forEach(c => {
            if (c && typeof c['core'] === 'undefined' || !c['core']) {
                if (typeof c['virtual'] === 'undefined' || !c['virtual']) {
                    if (typeof c['label'] === 'undefined') {c['label'] = c['name'];}
                    ret.push(c);
                }
            }
        });
        return ret.sort( (a,b) => a.label.localeCompare(b.label) );
    }

    getTransformsForDatatype(datatype: string, onlySimple?: boolean) {
        const ret = [];
        transforms.forEach(el => {
            if ( typeof el.datatypes === 'undefined' ||
            (el.datatypes.findIndex(dt => dt === datatype) > -1) ) {
                if (onlySimple && !el.simple) {return;}
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
        const def_op = this.getOperatorByName(DEFAULT_OPERATOR);
        if (def_op && (!def_op.datatypes || def_op.datatypes.includes(dt)) && (!def_op.hidden || !def_op.hidden.includes(dt))) {
            return def_op;
        }
        return this.getOperatorsForDatatype(dt)[0];
    }

    getTransformByName(name: string) {
        if (!name) {return this.defaultTransform();}
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

    getFolders(fmClass: string): Promise<IdlObject> {
        return this.pcrud.search(fmClass,
            { owner: this.auth.user().id(), 'simple_reporter': 'f', name: defaultSRFolderName },
            {}).toPromise();
    }

    getDefaultSRFolder(fmClass: string): Promise<IdlObject> {
        return this.pcrud.search(fmClass,
            { owner: this.auth.user().id(), 'simple_reporter': 't', name: defaultSRFolderName },
            {}).toPromise();
    }

    createDefaultSRFolder(fmClass: string): Promise<IdlObject> {
        const rf = this.idl.create(fmClass);
        rf.isnew(true);
        rf.owner(this.auth.user().id());
        rf.simple_reporter(true);
        rf.name(defaultSRFolderName);
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

        return this.net.request(
            'open-ils.reporter',
            'open-ils.reporter.template.retrieve',
            this.auth.token(), id, searchOps
        ).toPromise().then(t => this.maybeUpgradeTemplate(t));
    }

    maybeUpgradeTemplate(t: IdlObject): Promise<IdlObject> {
        const rtData = JSON.parse(t.data());
        if (rtData.version < 5) {
            this.upgradeXULTemplateData(t);
        }

        if (rtData.version < 6) {
            if (!rtData.simple_report) { // truly an old report
                this.upgradeAngJSTemplateData(t);
            } // else it is a Simple Reporter template, just leave it be
        }

        return of(t).toPromise();
    }

    loadReport(id: number): Promise<IdlObject> {
        const searchOps = {
            flesh: 2,
            flesh_fields: {
                rr: ['template','runs']
            }
        };
        return this.net.request(
            'open-ils.reporter',
            'open-ils.reporter.report.retrieve',
            this.auth.token(), id, searchOps
        ).toPromise().then(
            r => {
                return this.maybeUpgradeTemplate(r.template()).then(
                    t => { return r.template(t), r;}
                );
            }
        );
    }

    saveTemplate(
        templ: SRTemplate,
        scheduleNow = false
    ): Promise<any> { // IdlObject or Number? It depends!
        return this.saveSimpleTemplate(templ,scheduleNow,false);
    }

    buildReportData(
        templ: SRTemplate,
        isSimple = false
    ) {
        const rrData = {};
        rrData['__pivot_label'] = templ.pivotLabel;
        rrData['__pivot_data'] = templ.pivotData;
        rrData['__do_rollup'] = templ.doRollup ? 1 : 0;
        rrData['__record_bucket'] = templ.recordBucket;
        rrData['__bib_column_number'] = templ.bibColumnNumber;

        templ.filterFields.forEach((el, idx) => {
            if (isSimple || !el.with_value_input) {
                rrData[el.filter_placeholder] = el.force_filtervalues ? el.force_filtervalues : el.filter_value;
                if (el.datatype === 'org_unit' && el.operator.name === '= any') { // special case for org selector
                    const final_value = { transform: 'Bare', params: rrData[el.filter_placeholder] };
                    final_value['_org_family_primaryOrgId'] = el._org_family_primaryOrgId;
                    final_value['_org_family_includeAncestors'] = el._org_family_includeAncestors;
                    final_value['_org_family_includeDescendants'] = el._org_family_includeDescendants;
                    rrData[el.filter_placeholder] = final_value;
                }
            }
        });

        return rrData;
    }

    saveSimpleTemplate(
        templ: SRTemplate,
        scheduleNow = false,
        isSimple?: boolean
    ): Promise<any> { // IdlObject or Number? It depends!
        isSimple ??= true; // can't initialize an optional param in the definition, do it here

        const rtData = this.buildTemplateData(templ, isSimple);
        const rrData = this.buildReportData(templ, isSimple);

        const rtIdl = this.idl.create('rt');
        if (!templ.isNew) {rtIdl.id(templ.id);}
        rtIdl.isnew(!!(templ.isNew));
        rtIdl.name(templ.name);
        rtIdl.create_time(templ.create_time);
        rtIdl.description(templ.description);
        rtIdl.data(JSON.stringify(rtData));
        rtIdl.owner(this.auth.user().id());
        rtIdl.folder(this.templateFolder?.id());

        const rrIdl = this.idl.create('rr');
        if (isSimple) {
            rrIdl.isnew(!!(templ.id === -1));

            rrIdl.name(templ.name);
            rrIdl.data(JSON.stringify(rrData));
            rrIdl.owner(this.auth.user().id());
            rrIdl.folder(this.reportFolder.id());
            rrIdl.template(templ.id);
            rrIdl.create_time('now'); // rr create time is serving as the edit time
            // of the SR template as a whole

            rrIdl.recur(templ.recurring ? 't' : 'f');
            rrIdl.recurrence(templ.recurrence);
        }

        return this.pcrud.search('rt', { name: rtIdl.name(), folder: rtIdl.folder() })
            .pipe(defaultIfEmpty(rtIdl), map(existing => {
                if (templ.isNew && existing.id() !== rtIdl.id()) { // oh no! dup name
                    throw new Error(': Duplicate Name');
                }

                if (templ.isNew) { //
                    return this.pcrud.create(rtIdl).pipe(mergeMap(rt => {
                        if (isSimple) {
                            rrIdl.template(rt.id());
                            // after saving the rr, return an Observable of the rt
                            // to the caller
                            return this.pcrud.create(rrIdl).pipe(mergeMap(
                                rr => this.scheduleReport(templ, rr, scheduleNow).pipe(mergeMap(rs => of(rt)))
                            ));
                        }

                        return of(rt);
                    })).toPromise();
                } else if (!isSimple) { // edit mode, NOT simple reporter
                    return this.pcrud.update(rtIdl).pipe(mergeMap(_ => of(rtIdl))).toPromise();
                } else {
                    const emptyRR = this.idl.create('rr');
                    emptyRR.id('no_rr');
                    return this.pcrud.update(rtIdl).pipe(mergeMap(rtId => {
                    // we may or may not have the rr already created, so
                    // test and act accordingly
                        return this.pcrud.search('rr', { template: rtId }).pipe(defaultIfEmpty(emptyRR), mergeMap(rr => {
                            if (rr.id() === 'no_rr') {
                                rrIdl.isnew(true);
                                // Wrap the create() in a Promise to guarantee the observable
                                // completes and the related pcrud transaction is committed
                                // before the call to create the linked schedule is made.
                                return from(this.pcrud.create(rrIdl).toPromise()).pipe(mergeMap(rr2 =>
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

    saveReportDefinition (
        templ: SRTemplate,
        name: string,
        description: string,
        editExisting = false,
        scheduleNow = true
    ): Promise<any> { // IdlObject or Number? It depends!

        const rrData = this.buildReportData(templ);
        const rrIdl = editExisting ? templ.rrIdl : this.idl.create('rr');

        if (editExisting) {
            if (!rrIdl || !rrIdl.id()) {
                throw new Error(': No report object to edit!');
            }
            rrIdl.ischanged(1);
        } else {
            rrIdl.isnew(1);
            rrIdl.owner(this.auth.user().id());
            rrIdl.template(templ.id);
        }
        rrIdl.name(name);
        rrIdl.description(description);
        rrIdl.data(JSON.stringify(rrData));
        rrIdl.folder(this.reportFolder.id());
        rrIdl.recur(templ.recurring ? 't' : 'f');
        rrIdl.recurrence(templ.recurrence);

        if (editExisting) {
            return this.pcrud.update(rrIdl).pipe(mergeMap( _ => {
                return this.scheduleReport(templ, rrIdl, scheduleNow).pipe(mergeMap(rs => of(templ.id)));
            })).toPromise();
        } else {
            const emptyRR = this.idl.create('rr');
            emptyRR.id('no_rr');
            return this.pcrud.search('rr', { name: rrIdl.name(), folder: rrIdl.folder() })
                .pipe(defaultIfEmpty(emptyRR), mergeMap(existing => {
                    console.log('Searched for duplicate rr object: ', existing);
                    if (existing.id() !== 'no_rr') { // oh no! dup name
                        throw new Error(': Duplicate Name');
                    }

                    return this.pcrud.create(rrIdl).pipe(mergeMap(rr2 => {
                        console.log('Saved rr object: ', rr2);
                        return this.scheduleReport(templ, rr2, scheduleNow).pipe(mergeMap(rs => of(templ.id)));
                    }));

                })).toPromise();
        }
    }

    scheduleReport(templ: SRTemplate, rr: IdlObject, scheduleNow: boolean): Observable<IdlObject> {
        const rs = this.idl.create('rs');
        if (!scheduleNow) {
            return of(rs); // return a placeholder
        }
        rs.isnew(true);
        rs.report(rr.id());
        rs.folder(this.outputFolder.id());
        rs.runner(this.auth.user().id());
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
        rs.new_record_bucket(templ.newRecordBucket ? 't' : 'f');
        rs.existing_record_bucket(templ.existingRecordBucket ? 't' : 'f');

        // clear any un-run schedules, then add the new one
        return this.pcrud.search(
            'rs', { report: rr.id(), start_time: null }, {}, {atomic: true}
        ).pipe(mergeMap(old_rs => {
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
        templ: SRTemplate,
        isSimple = false
    ) {
        const fmClass = templ.fmClass;
        const localClasses = this.idl.classes;
        const sourceClass = localClasses[fmClass];
        const md5Name = Md5.hashStr(fmClass); // Just the one with SR since there are no joins
        let conditionCount = 0;

        // The simplified template that can be edited and re-saved
        const simpleReport = {
            name: templ.name,
            fmClass: fmClass,
            displayFields: [...templ.displayFields],
            orderByNames: [...templ.orderByNames],
            filterFields: [...templ.filterFields],
        };
        const reportTemplate = {
            simple_report: simpleReport,
            version: 7,
            doc_url: templ.doc_url,
            core_class: fmClass,
            'from': {
                alias: md5Name,
                path: fmClass + '-' + fmClass,
                table: sourceClass.source ?? sourceClass.table,
                idlclass: fmClass,
                label: sourceClass.label,
                join: {}
            },
            select: [],
            where: [],
            having: [],
            order_by: [],
            relations: {}
        };

        reportTemplate.relations[md5Name] = {...reportTemplate['from']};

        // fill in select[] and make sure FROM paths are set
        templ.displayFields.forEach((el, idx) => {
            const rel_md5Name = makePathHash(el.path); // Just the one with SR since there are no joins

            reportTemplate.select.push({
                alias: el.alias,
                path: el.treeNodeId,
                relation: rel_md5Name,
                column: {
                    colname: el.name,
                    transform: el.transform.name,
                    aggregate: el.transform.aggregate
                }
            });

            reify_from_clause_relations(el,reportTemplate);

        }); // select[]

        // where[] and having[] are the same save for aggregate == true
        templ.filterFields.forEach((el, idx) => {
            const rel_md5Name = makePathHash(el.path); // Just the one with SR since there are no joins
            let whereObj = {};

            whereObj = {
                path: fmClass + '-' + el.name,
                relation: rel_md5Name,
                column: {
                    colname: el.name,
                    transform: el.transform.name,
                    aggregate: el.transform.aggregate
                },
                condition: {}
            };

            reify_from_clause_relations(el,reportTemplate);

            if (isSimple || !el.with_value_input) {
                if (el.operator.arity > 0) {
                    whereObj['condition'][el.operator.name] = '::P' + conditionCount;
                    el.filter_placeholder = 'P' + conditionCount;
                    conditionCount++;
                } else { // is [not] null, don't burn a placeholder. This is important for backward compat, so old templates and new reports have placeholders that line up
                    whereObj['condition'][el.operator.name] = null;
                }
            } else {
                el.filter_placeholder = null;
                whereObj['condition'][el.operator.name] = el.filter_value;
            }

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
            const el = templ.displayFields[templ.displayFields.findIndex(fl => fl.treeNodeId === ob || fl.name === ob)];
            reportTemplate.order_by.push({
                alias: el.alias,
                path: fmClass + '-' + el.name,
                relation: makePathHash(el.path),
                direction: el.direction ? el.direction : 'ascending',
                column: {
                    colname: el.name,
                    transform: el.transform.name,
                    aggregate: el.transform.aggregate
                }
            });
        });

        return reportTemplate;

        // ---- End of logic ----

        function makePathHash(treeNodeList) {
            if (!treeNodeList) {
                return md5Name;
            }

        	let pathHash = '';
    	    treeNodeList.forEach((n,i) => {
	            if (i) {
            	    pathHash += ' -> ';
	            	if (n.stateFlag) {pathHash += ' [Required]';}
        	    }
	            if (n.callerData.fmField?.name) {
	                pathHash += n.callerData.fmField.name + '.';
	            }
    	        pathHash += n.callerData.fmClass;
        	});
            return Md5.hashStr(pathHash);
	    }

        function reify_from_clause_relations (el, reportTemplate) {
            if (!el.path) {return;}

            let remaining_steps = el.path.length - 1;
            let step_ind = 0;
            let from_branch = reportTemplate['from'];
            const steps_so_far = [];
            do { // loop through the path objects (TreeNode list) to set up joins
                const step = el.path[step_ind];
                steps_so_far.push(step);

                const step_hash = makePathHash(steps_so_far);
                if (step.callerData.fmField) { // we're past the top of the join path
                    const step_field_name = step.callerData.fmField.name;
                    const new_join_path_key = step_field_name + '-' + step_hash;
                    const step_table = localClasses[step.callerData.fmClass];

                    from_branch['join'] ??= {};
                    if (!from_branch['join'][new_join_path_key]) {
                        from_branch['join'][new_join_path_key] = {
                            type: (step.stateFlag ? 'inner' : 'left'),
                            key: step.callerData.fmField.key,
                            alias: step_hash,
                            idlclass: step.callerData.fmField.class,
                            label: el.path_label,
                            table:  step_table.source ?? step_table.table
                        };
                        console.log('adding '+(step.stateFlag ? 'inner' : 'left')+'-join branch for path key: ' + new_join_path_key);
                    }

                    reportTemplate.relations[step_hash] = from_branch['join'][new_join_path_key];
                    from_branch = from_branch['join'][new_join_path_key];
                }

                step_ind++;
            } while (remaining_steps--);
        }

    }

    upgradeAngJSTemplateData = function(template: IdlObject) {
        const localIdl = this.idl;

        const newSRTempl = new SRTemplate();
        newSRTempl.isNew = false;
        newSRTempl.id = template.id();
        newSRTempl.create_time = template.create_time();
        newSRTempl.name = template.name();
        newSRTempl.description = template.description();

        const oldData = JSON.parse(template.data());
        newSRTempl.fmClass = oldData.core_class;
        newSRTempl.doc_url = oldData.doc_url;

        const md5Name = Md5.hashStr(newSRTempl.fmClass); // Just the one with SR since there are no joins

        const dF = [];
        oldData.display_cols.forEach(c => {
            const converted_path = convertAngJSPathForCol(c);
            if (c.transform?.transform === 'count') {
                c.transform.transform = 'count_distinct'; // we only do count_distinct now
            }

            dF.push({
                class: converted_path[converted_path.length - 1].classname,
                name: c.name,
                label: c.label,
                alias: c.alias || c.label || c.name,
                field_doc: c.doc_text,
                field_doc_supplied: !!c.doc_text,
                datatype: c.datatype,
                path_label: c.path_label,
                treeNodeId: c.path_label.replace(/\s+/g, '_') + '_' + c.name,
                transform: this.getTransformByName(c.transform.transform),
                path: converted_path,
                relation: makePathHashOrNull(converted_path) || md5Name
            });
        });

        const fF = [];
        oldData.filter_cols.forEach(c => {
            const converted_path = convertAngJSPathForCol(c);
            if (c.transform?.transform === 'count') {
                c.transform.transform = 'count_distinct'; // we only do count_distinct now
            }

            const valid_operators = this.getOperatorsForDatatype(c.datatype);
            if (!valid_operators.map(t => t.name).includes(c.operator.operator)) {
                // XXX special case for bool and org_unit '='
                if (['bool','org_unit'].includes(c.datatype)
					&& c.operator.op === '='
                    && c.value !== 'undefined'
                ) {
                    c.operator.op = '= any';
                    c.value = '{' + c.value + '}';
                }
            }

            const our_operator = this.getOperatorByName(c.operator.op);
            let our_value = c.value;
            if (!our_value && our_operator.arity == 2) {our_value = [];} // between needs an array

            fF.push({
                class: converted_path[converted_path.length - 1].classname,
                name: c.name,
                label: c.label,
                field_doc: c.doc_text,
                field_doc_supplied: !!c.doc_text,
                datatype: c.datatype,
                treeNodeId: c.path_label.replace(/\s+/g, '_') + '_' + c.name,
                transform: this.getTransformByName(c.transform.transform),
                operator: our_operator,
                path: converted_path,
                relation: makePathHashOrNull(converted_path) || md5Name,
                with_value_input: (typeof c.value === 'undefined') ? false : true,
                filter_value: our_value
            });
        });

        newSRTempl.displayFields = dF;
        newSRTempl.filterFields = fF;
        newSRTempl.orderByNames = dF.map(d => d.treeNodeId),

        template.data(JSON.stringify(this.buildTemplateData(newSRTempl)));
        return template;

        // ---- End of logic ----

        function convertAngJSPathForCol(oldCol) {
            const newPath = [];
            oldCol.path.forEach((old,ind) => {
                const newPathNode = {
                    label: old.label,
                    stateFlag: (old.jtype === 'inner') ? true : false,
                    callerData: { fmClass: old.classname }
                };
                if (old.uplink) {
                    const uplink_from = old.from?.split('.').pop(); // get the last class step in the "from" member, if it exists
                    newPathNode.callerData['fmField'] = {
                        key: old.uplink.key, // my (right hand side) join key
                        name: (uplink_from && ['has_many','might_have'].includes(old.uplink.reltype)) ? // do we have enough information and the reltype conditions to replace the left hand side key?
                                localIdl.classes[uplink_from].pkey : old.uplink.name, // field from left side of join. see: treeFromRptType() in ../full/editor.component.ts
                        reltype: old.uplink.reltype, // reltype from link from left side of join
                        class: newPathNode.callerData.fmClass // same as fmClass
                    };
                }

                newPath.push(newPathNode);
            });

            return newPath;
        }

        function makePathHashOrNull(treeNodeList) {
            if (!treeNodeList || treeNodeList.length <= 1) {
                return null;
            }

        	let pathHash = '';
    	    treeNodeList.forEach((n,i) => {
	            if (i) {
            	    pathHash += ' -> ';
	            	if (n.stateFlag) {pathHash += ' [Required]';}
        	    }
    	        pathHash += n.callerData.fmClass;
        	});
            return Md5.hashStr(pathHash);
	    }

    };

    upgradeXULTemplateData = function(template: IdlObject) {
        // handy for (copied) non-arrow closures below, which can't use "this"
        const localIdl = this.idl;

        template.name(template.name() + ' (converted from XUL)');
        const template_data = JSON.parse(template.data());

        template_data.upgraded_from ??= [];
        template_data.upgraded_from.push(template_data.version);

        template_data.version = 5;

        let order_by;
        const rels = [];
        for (const key in template_data.rel_cache) {
            if (key == 'order_by') {
                order_by = template_data.rel_cache[key];
            } else {
                rels.push(template_data.rel_cache[key]);
            }
        }

        // preserve the old select order for the display cols
        const sel_order = {};
        template_data.select.map(function(val, idx) {
            // set key to unique value easily derived from relcache
            sel_order[val.relation + val.column.colname] = idx;
        });

        template_data['display_cols'] = [];
        template_data['filter_cols'] = [];

        rels.map(function(rel) {
            _buildCols(rel, 'dis_tab');
            _buildCols(rel, 'filter_tab', template_data.filter_cols?.length);
            _buildCols(rel, 'aggfilter_tab', template_data.filter_cols?.length);
        });

        template_data['display_cols'].sort(function(a, b){return a.index - b.index;});

        template.data(JSON.stringify(template_data));
        return template;

        // ---- End of logic ----

        function buildNode (cls, args) {
            if (!cls) {return null;}

            const n = localIdl.classes[cls];
            if (!n) {return null;}

            if (!args) {args = { label : n.label };}

            args.id = cls;
            if (args.from) {args.id = args.from + '.' + args.id;}

            return Object.assign( args, {
                // idl     : localIdl.constructors[cls], // commented out because we don't need it, but here's how to do what v5 did
                uplink  : args.link,
                classname: cls,
                struct  : n,
                table   : n.table,
                fields  : n.fields,
                links   : n.fields.filter(x => x.type == 'link'),
                children: []
            });
        }

        function _convertPath(orig, rel) {
            const newPath = [];

            const table_path = rel.path.split(/\./);
            if (table_path.length > 1 || rel.path.indexOf('-') > -1) {table_path.push( rel.idlclass );}

            const prev_type = '';
            let prev_link = '';
            table_path.forEach(function(link) {
                const cls = link.split(/-/)[0];
                const fld = link.split(/-/)[1];
                const args = {
                    label : localIdl.classes[cls].label
                };
                if (prev_link != '') {
                    const link_parts = prev_link.split(/-/);
                    args['from'] = link_parts[0];
                    const join_parts = link_parts[1].split(/>/);
                    const prev_col = join_parts[0];
                    localIdl.classes[prev_link.split(/-/)[0]].fields.forEach(function(f) {
                        if (prev_col == f.name) {
                            args['link'] = {...f};
                        }
                    });
                    args['jtype'] = join_parts[1]; // frequently undefined
                }
                newPath.push(buildNode(cls, args));
                prev_link = link;
            });
            return newPath;

        }

        function _buildCols(rel, tab_type, col_idx = 0) {

            const col_type = (tab_type === 'dis_tab') ?  'display_cols' : 'filter_cols';

            for (const col_key in rel.fields[tab_type]) {
                const orig = rel.fields[tab_type][col_key];
                const col_obj = {
                    name        : orig.colname,
                    path        : _convertPath(orig, rel),
                    label       : orig.alias,
                    datatype    : orig.datatype,
                    doc_text    : orig.field_doc,
                    transform   : {
                        label     : orig.transform_label,
                        transform : orig.transform,
                        aggregate : (orig.aggregate == 'undefined') ? undefined : orig.aggregate  // old structure sometimes has undefined as a quoted string
                    },
                    path_label  : rel.label.replace('::', '->')
                };
                if (col_type == 'filter_cols') {
                    col_obj['operator'] = {
                        op        : orig.op,
                        label     : orig.op_label
                    };
                    col_obj['index'] = col_idx++;
                    if ('value' in orig.op_value) {
                        col_obj['value'] = orig.op_value.value;
                    }
                } else { // display
                    col_obj['index'] = sel_order[rel.alias + orig.colname];
                }

                template_data[col_type].push(col_obj);
            }
        }

    };

    getPendingOutputDatasource(o: IdlObject = null) {
        return this.getOutputDatasource(false,o);
    }

    getCompleteOutputDatasource(o: IdlObject = null) {
        return this.getOutputDatasource(true,o);
    }

    getOutputDatasource(withComplete = true, sourceFilterObject?: IdlObject) {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort?: any[]) => {

            // start setting up query
            const query: Object = {};

            if (sourceFilterObject?.classname === 'rr') {
                query['report'] = sourceFilterObject.id();
            } else if (sourceFilterObject?.classname === 'rof') {
                query['folder'] = sourceFilterObject.id();
            } else if (sourceFilterObject?.classname === 'au') {
                query['runner'] = sourceFilterObject.id();
            } else {
                query['folder'] = this.outputFolder.id();
            }

            return this.net.request(
                'open-ils.reporter',
                'open-ils.reporter.schedule.retrieve_by_folder',
                this.auth.token(), query, {offset: pager.offset, limit: pager.limit} , withComplete
            ).pipe(
                map((rows: any[]) => rows.map(row => {
                    return {
                        template_name: row.report().template().name(),
                        report_name: row.report().name(),
                        complete_time: row.complete_time(),
                        start_time: row.start_time(),
                        run_time: row.run_time(),
                        id: row.id(),
                        report_id: row.report().id(),
                        template_id: row.report().template().id(),
                        error_code: row.error_code(),
                        error_text: row.error_text(),
                        _rs: row
                    };
                })),
                switchMap((rows: any[]) => from(rows))
            );
        };

        return gridSource;
    }


    getSOutputDatasource(withPending = false, withComplete = true, sourceFilterObject?: IdlObject) {
        const gridSource = new GridDataSource();
        let output_source = 'rcr';

        if (withComplete) {
            gridSource.sort = [{ name: 'complete_time', dir: 'DESC' }];
        } else if (withPending) {
            output_source = 'rs';
            gridSource.sort = [{ name: 'run_time', dir: 'DESC' }];
        }

        gridSource.getRows = (pager: Pager, sort: any[]) => {

            // start setting up query
            const base: Object = {};

            let folder_col = 'output_folder';
            if (withPending) {
                folder_col = 'folder';
                if (!withComplete) {
                    base['complete_time'] = { '=': null };
                }
            }

            if (sourceFilterObject?.classname === 'rr') {
                base['report'] = sourceFilterObject.id();
            } else if (sourceFilterObject?.classname === 'rof') {
                base[folder_col] = sourceFilterObject.id();
            } else if (sourceFilterObject?.classname === 'au') {
                base['owner'] = sourceFilterObject.id();
            } else {
                base['runner'] = this.auth.user().id();
                base[folder_col] = this.outputFolder.id();
            }

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
                orderBy[output_source] = sort[0].name + ' ' + sort[0].dir;
            }

            const searchOpts = {
                flesh: 2,
                flesh_fields: {},
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            if (!withPending) {
                searchOpts.flesh_fields[output_source] = ['run'];
            } else {
                searchOpts.flesh_fields['rs'] = ['report'];
                searchOpts.flesh_fields['rr'] = ['template'];
            }

            return this.pcrud.search(output_source, query, searchOpts)
                .pipe(map(row => {
                    if ( this.evt.parse(row) ) {
                        throw new Error(row);
                    } else {
                        return {
                            simple_name: withPending ? row.report().template().name() : row.template_name(),
                            template_name: withPending ? row.report().template().name() : row.template_name(),
                            report_name: withPending ? row.report().name() : row.report_name(),
                            complete_time: row.complete_time(),
                            start_time: row.start_time(),
                            run_time: row.run_time(),
                            id: withPending ? row.id() : row.run().id(),
                            report_id: withPending ? row.report().id() : row.report(),
                            template_id: withPending ? row.report().template().id() : row.template(),
                            error_code: withPending ? row.error_code() : row.run().error_code(),
                            error_text:withPending ? row.error_text() :  row.run().error_text(),
                            _rs: withPending ? row : row.run()
                        };
                    }
                }));

        };

        return gridSource;
    }

    getTemplatesSearchDatasource(str: string, field: string, fldr: IdlObject) {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {
            if (!str) {return of();}
            let fields = null;
            if (field) {fields = [field];}

            return this.net.request(
                'open-ils.reporter',
                'open-ils.reporter.search.templates',
                this.auth.token(), {
                    query : str,
                    folder: fldr?.id(),
                    fields : fields
                }
            ).pipe(map(row => {
			    const rowData = JSON.parse(row.data());
                return {
                    name: row.name(),
                    rt_id: row.id(),
                    create_time: row.create_time(),
                    description: row.description(),
                    owner: row.owner().usrname(),
                    documentation: rowData.doc_url,
                    version: rowData.version,
                    folder: row.folder().name(),
                    _rt: row
                };
            }));
        };

        return gridSource;
    }

    getTemplatesDatasource() {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) {
                orderBy.rt = sort[0].name + ' ' + sort[0].dir;
            } else {
                orderBy.rt = 'name ASC';
            }

            // start setting up query
            const base: Object = {};
            base['folder'] = this.templateFolder?.id();

            const query: any = new Array();
            query.push(base);

            // and add any filters
            Object.keys(gridSource.filters).forEach(key => {
                Object.keys(gridSource.filters[key]).forEach(key2 => {
                    query.push(gridSource.filters[key][key2]);
                });
            });

            return this.net.request(
                'open-ils.reporter',
                'open-ils.reporter.folder_data.retrieve.stream',
                this.auth.token(), 'template', query,
                pager.limit, pager.offset, orderBy
            ).pipe(map(row => {
                const rowData = JSON.parse(row.data());
                const rowFolder = this.templateFolderList.find(f => f.id() === row.folder());

                return {
                    name: row.name(),
                    rt_id: row.id(),
                    create_time: row.create_time(),
                    description: row.description(),
                    owner: row.owner().usrname(),
                    documentation: rowData.doc_url,
                    version: rowData.version,
                    folder: rowFolder?.name(),
                    _rt: row
                };
            }));
        };

        return gridSource;
    }

    getReportsDatasource(sourceFilterObject?: IdlObject) {
        const gridSource = new GridDataSource();

     	gridSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) {
                if (sort[0].name === 'recurring') {
                    // special case because the grid column path
                    // does not match the DB column name
                    orderBy.rr = 'recur' + ' ' + sort[0].dir;
                } else {
                    orderBy.rr = sort[0].name + ' ' + sort[0].dir;
                }
            } else {
                orderBy.rr = 'name ASC';
            }

            // start setting up query
            const base: Object = {};
            if (sourceFilterObject?.classname === 'rt') {
                base['template'] = sourceFilterObject.id();
            } else if (sourceFilterObject?.classname === 'rrf') {
                base['folder'] = sourceFilterObject.id();
            } else if (sourceFilterObject?.classname === 'au') {
                base['owner'] = sourceFilterObject.id();
            } else {
                base['folder'] = this.reportFolder?.id();
            }

            const query: any = new Array();
            query.push(base);

            // and add any filters
            Object.keys(gridSource.filters).forEach(key => {
                Object.keys(gridSource.filters[key]).forEach(key2 => {
                    if (key === 'recurring') {
                        // special case because the grid column path
                        // does not match the DB column name
                        query.push({
                            recur: gridSource.filters[key][key2]['recurring']
                        });
                    } else {
                        query.push(gridSource.filters[key][key2]);
                    }
                });
            });

            return this.net.request(
                'open-ils.reporter',
                'open-ils.reporter.folder_data.retrieve.stream',
                this.auth.token(), 'report', query,
                pager.limit, pager.offset, orderBy
            ).pipe(map(row => {
                // TODO cap the parallelism
                const rowFolder = this.reportFolderList.find(f => f.id() === row.folder());

                return this.net.request(
                    'open-ils.reporter',
                    'open-ils.reporter.template.retrieve',
				    this.auth.token(), row.template()
                ).pipe(map(t => {
				    const rowData = JSON.parse(t.data());

                    return {
                        name: row.name(),
                        rr_id: row.id(),
                        recurring: row.recur(),
                        recurrence: row.recurrence(),
                        create_time: row.create_time(),
                        description: row.description(),
                        owner: row.owner().usrname(),
                        documentation: rowData.doc_url,
                        version: rowData.version,
                        folder: rowFolder?.name(),
                        _rr: row
                    };
                }));
            }),concatMap(x => x));
        };

        return gridSource;
    }

    getSReportsDatasource() {
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
            base['folder'] = this.templateFolder?.id();

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
                private svc: ReporterService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        return from(this.perm.hasWorkPermHere('RUN_SIMPLE_REPORTS')).pipe(mergeMap(
            permResult => {
                if (permResult['RUN_SIMPLE_REPORTS']) {
                    return Promise.all([
                        this.svc._initSRFolders()
                    ]);
                } else {
                    this.router.navigate(['/staff/no_permission']);
                    return EMPTY;
                }
            }
        )).toPromise();
    }

}

@Injectable()
export class FullReporterServiceResolver implements Resolve<Promise<any[]>> {

    constructor(
                private router: Router,
                private perm: PermService,
                private svc: ReporterService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Promise<any[]> {

        return from(this.perm.hasWorkPermHere('RUN_REPORTS')).pipe(mergeMap(
            permResult => {
                if (permResult['RUN_REPORTS']) {
                    return EMPTY; // XXX short circuit
                    return Promise.all([
                        // this.svc._initFolders()
                    ]);
                } else {
                    this.router.navigate(['/staff/no_permission']);
                    return EMPTY;
                }
            }
        )).toPromise();
    }

}

