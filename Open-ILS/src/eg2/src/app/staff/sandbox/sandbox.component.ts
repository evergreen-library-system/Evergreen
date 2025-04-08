/* eslint-disable no-magic-numbers */

import {timer as observableTimer, Observable} from 'rxjs';
import {Component, OnInit, ViewChild, Input, TemplateRef} from '@angular/core';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringService} from '@eg/share/string/string.service';
import {map, take} from 'rxjs/operators';
import {GridDataSource, GridColumn, GridRowFlairEntry, GridCellTextGenerator} from '@eg/share/grid/grid';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {Pager} from '@eg/share/util/pager';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {PrintService} from '@eg/share/print/print.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {NgbDate} from '@ng-bootstrap/ng-bootstrap';
import {FormGroup, FormControl} from '@angular/forms';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PatronNoteDialogComponent} from '@eg/staff/share/patron/note-dialog.component';
import {FormatService} from '@eg/core/format.service';
import {StringComponent} from '@eg/share/string/string.component';
import {GridComponent} from '@eg/share/grid/grid.component';
import * as Moment from 'moment-timezone';
import {SampleDataService} from '@eg/share/util/sample-data.service';
import {HtmlToTxtService} from '@eg/share/util/htmltotxt.service';
import {Z3950SearchComponent} from '@eg/staff/share/z3950-search/z3950-search.component';

@Component({
    templateUrl: 'sandbox.component.html',
    styles: ['.date-time-input.ng-invalid {border: 5px purple solid;}',
        '.date-time-input.ng-valid {border: 5px green solid; animation: slide 5s linear 1s infinite alternate;}',
        '@keyframes slide {0% {margin-inline-start:0px;} 50% {margin-inline-start:200px;}}']
})
export class SandboxComponent implements OnInit {

    @ViewChild('progressDialog', { static: true })
    private progressDialog: ProgressDialogComponent;

    @ViewChild('dateSelect', { static: false })
    private dateSelector: DateSelectComponent;

    @ViewChild('printTemplate', { static: true })
    private printTemplate: TemplateRef<any>;

    @ViewChild('fmRecordEditor', { static: true })
    private fmRecordEditor: FmRecordEditorComponent;

    @ViewChild('numConfirmDialog', { static: true })
    private numConfirmDialog: ConfirmDialogComponent;

    public numThings = 0;

    @ViewChild('bresvEditor', { static: true })
    private bresvEditor: FmRecordEditorComponent;

    @ViewChild('noteDialog', {static: false}) noteDialog: PatronNoteDialogComponent;


    // @ViewChild('helloStr') private helloStr: StringComponent;

    gridDataSource: GridDataSource = new GridDataSource();

    cbEntries: ComboboxEntry[];
    // supplier of async combobox data
    cbAsyncSource: (term: string) => Observable<ComboboxEntry>;

    btSource: GridDataSource = new GridDataSource();
    btGridCellTextGenerator: GridCellTextGenerator;
    acpSource: GridDataSource = new GridDataSource();
    eventsDataSource: GridDataSource = new GridDataSource();
    editSelected: (rows: IdlObject[]) => void;
    @ViewChild('acpGrid', { static: true }) acpGrid: GridComponent;
    @ViewChild('acpEditDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: true }) updateFailedString: StringComponent;
    world = 'world'; // for local template version
    btGridTestContext: any = {hello : this.world};

    renderLocal = false;

    testDate: any;

    testStr: string;
    @Input() set testString(str: string) {
        this.testStr = str;
    }

    oneBtype: IdlObject;

    name = 'Jane';

    dynamicTitleText: string;

    badOrgForm: FormGroup;

    ranganathan: FormGroup;

    dateObject: Date = new Date();

    simpleCombo: ComboboxEntry;
    kingdom: ComboboxEntry;

    complimentEvergreen: (rows: IdlObject[]) => void;
    notOneSelectedRow: (rows: IdlObject[]) => boolean;

    // selector field value on metarecord object
    aMetarecord: string;

    // file-reader example
    fileContents:  Array<string>;

    // cross-tab communications example
    private sbChannel: any;
    sbChannelText: string;
    myTimeForm: FormGroup;

    locId = 1; // Stacks
    aLocation: IdlObject; // acpl
    orgClassCallback: (orgId: number) => string;

    circDaily: IdlObject;
    circHourly: IdlObject;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private strings: StringService,
        private toast: ToastService,
        private format: FormatService,
        private printer: PrintService,
        private samples: SampleDataService,
        private h2txt: HtmlToTxtService
    ) {
        // BroadcastChannel is not yet defined in PhantomJS and elsewhere
        this.sbChannel = (typeof BroadcastChannel === 'undefined') ?
            {} : new BroadcastChannel('eg.sbChannel');
        this.sbChannel.onmessage = (e) => this.sbChannelHandler(e);

        this.orgClassCallback = (orgId: number): string => {
            if (orgId === 1) { return 'font-weight-bold'; }
            return orgId <= 3 ? 'text-info' : 'text-danger';
        };
    }

    ngOnInit() {
        this.badOrgForm = new FormGroup({
            'badOrgSelector': new FormControl(
                {'id': 4, 'includeAncestors': false, 'includeDescendants': true}, (c: FormControl) => {
                    // An Angular custom validator
                    if (c.value.orgIds && c.value.orgIds.length > 5) {
                        return { tooMany: 'That\'s too many fancy libraries!' };
                    } else {
                        return null;
                    }
                } )
        });

        this.ranganathan = new FormGroup({
            'law': new FormControl('second', (c: FormControl) => {
                // An Angular custom validator
                if ('wrong' === c.value.id || c.value.freetext) {
                    return { notALaw: 'That\'s not a real law of library science!' };
                } else {
                    return null;
                }
            } )
        });

        this.badOrgForm.get('badOrgSelector').valueChanges.subscribe(bad => {
            this.toast.danger('The fanciest libraries are: ' + JSON.stringify(bad.orgIds));
        });

        this.ranganathan.get('law').valueChanges.subscribe(l => {
            this.toast.success('You chose: ' + l.label);
        });

        this.kingdom = {id: 'Bacteria', label: 'Bacteria'};

        this.gridDataSource.data = [
            {name: 'Jane', state: 'AZ'},
            {name: 'Al', state: 'CA'},
            {name: 'The Tick', state: 'TX'}
        ];

        this.pcrud.retrieveAll('cmrcfld', {order_by: {cmrcfld: 'name'}})
            .subscribe(format => {
                if (!this.cbEntries) { this.cbEntries = []; }
                this.cbEntries.push({id: format.id(), label: format.name()});
            });

        this.cbAsyncSource = term => {
            return this.pcrud.search(
                'cmrcfld',
                {name: {'ilike': `%${term}%`}}, // could -or search on label
                {order_by: {cmrcfld: 'name'}}
            ).pipe(map(marcField => {
                return {id: marcField.id(), label: marcField.name()};
            }));
        };

        this.btSource.getRows = (pager: Pager, sort: any[]) => {

            const orderBy: any = {cbt: 'name'};
            if (sort.length) {
                orderBy.cbt = sort[0].name + ' ' + sort[0].dir;
            }

            return this.pcrud.retrieveAll('cbt', {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            }).pipe(map(cbt => {
                // example of inline fleshing
                cbt.owner(this.org.get(cbt.owner()));
                cbt.datetime_test = new Date();
                this.oneBtype = cbt;
                return cbt;
            }));
        };

        // GridCellTextGenerator for the btGrid; note that this
        // also demonstrates that a GridCellTextGenerator only has
        // access to the row, and does not have access to any additional
        // context that might be passed to a cellTemplate
        this.btGridCellTextGenerator = {
            test: row => 'HELLO universe ' + row.id()
        };

        this.acpSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {acp: 'id'};
            if (sort.length) {
                orderBy.acp = sort[0].name + ' ' + sort[0].dir;
            }

            // base query to grab everything
            const base: Object = {};
            base[this.idl.classes['acp'].pkey] = {'!=' : null};
            const query: any = new Array();
            query.push(base);

            // and add any filters
            Object.keys(this.acpSource.filters).forEach(key => {
                Object.keys(this.acpSource.filters[key]).forEach(key2 => {
                    query.push(this.acpSource.filters[key][key2]);
                });
            });
            return this.pcrud.search('acp',
                query, {
                    flesh: 1,
                    flesh_fields: {acp: ['location', 'status', 'creator', 'editor']},
                    offset: pager.offset,
                    limit: pager.limit,
                    order_by: orderBy
                });
        };

        this.eventsDataSource.getRows = (pager: Pager, sort: any[]) => {

            const orderEventsBy: any = {atevdef: 'name'};
            if (sort.length) {
                orderEventsBy.atevdef = sort[0].name + ' ' + sort[0].dir;
            }

            const base: Object = {};
            base[this.idl.classes['atevdef'].pkey] = {'!=' : null};
            const query: any = new Array();
            query.push(base);

            console.log(JSON.stringify(this.eventsDataSource.filters));

            Object.keys(this.eventsDataSource.filters).forEach(key => {
                Object.keys(this.eventsDataSource.filters[key]).forEach(key2 => {
                    query.push(this.eventsDataSource.filters[key][key2]);
                });
            });

            return this.pcrud.search('atevdef', query, {
                flesh: 1,
                flesh_fields: {atevdef: ['hook', 'validator', 'reactor']},
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderEventsBy
            });
        };

        this.editSelected = (idlThings: IdlObject[]) => {

            // Edit each IDL thing one at a time
            const editOneThing = (thing: IdlObject) => {
                if (!thing) { return; }

                this.showEditDialog(thing).then(
                    () => editOneThing(idlThings.shift()));
            };

            editOneThing(idlThings.shift());
        };
        this.acpGrid.onRowActivate.subscribe(
            (acpRec: IdlObject) => { this.showEditDialog(acpRec); }
        );

        this.complimentEvergreen = (rows: IdlObject[]) => alert('Evergreen is great!');
        this.notOneSelectedRow = (rows: IdlObject[]) => (rows.length !== 1);

        this.pcrud.retrieve('bre', 1, {}, {fleshSelectors: true})
            .subscribe(bib => {
            // Format service will automatically find the selector
            // value to display from our fleshed metarecord field.
                this.aMetarecord = this.format.transform({
                    value: bib.metarecord(),
                    idlClass: 'bre',
                    idlField: 'metarecord'
                });
            });

        const b = this.idl.create('bresv');
        b.cancel_time('2019-03-25T11:07:59-0400');
        this.bresvEditor.mode = 'create';
        this.bresvEditor.record = b;

        this.myTimeForm = new FormGroup({
            'datetime': new FormControl(Moment([]), (c: FormControl) => {
                // An Angular custom validator
                if (c.value.year() < 2019) {
                    return { tooLongAgo: 'That\'s before 2019' };
                } else {
                    return null;
                }
            } )
        });

        const str = 'C&#xe9;sar&nbsp;&amp;&nbsp;Me';
        console.log(this.h2txt.htmlToTxt(str));

        const org =
            this.org.list().filter(o => o.ou_type().can_have_vols() === 't')[0];
        this.circDaily = this.idl.create('circ');
        this.circDaily.duration('1 day');
        this.circDaily.due_date(new Date().toISOString());
        this.circDaily.circ_lib(org.id());

        this.circHourly = this.idl.create('circ');
        this.circHourly.duration('1 hour');
        this.circHourly.due_date(new Date().toISOString());
        this.circHourly.circ_lib(org.id());
    }

    sbChannelHandler = msg => {
        setTimeout(() => { this.sbChannelText = msg.data.msg; });
    };

    sendMessage($event) {
        this.sbChannel.postMessage({msg : $event.target.value});
    }

    // Example of click handler for row action
    complimentEvergreen2(rows: IdlObject[]) {
        alert('I know, right?');
    }

    openEditor() {
        this.fmRecordEditor.open({size: 'lg'}).subscribe(
            pcrudResult => console.debug('Record editor performed action'),
            (err: unknown) => console.error(err),
            () => console.debug('Dialog closed')
        );
    }

    btGridRowClassCallback(row: any): string {
        if (row.id() === 1) {
            return 'text-uppercase font-weight-bold text-danger';
        }
    }

    btGridRowFlairCallback(row: any): GridRowFlairEntry {
        const flair = {icon: null, title: null};
        if (row.id() === 2) {
            flair.icon = 'priority_high';
            flair.title = 'I Am ID 2';
        } else if (row.id() === 3) {
            flair.icon = 'not_interested';
        }
        return flair;
    }

    // apply to all 'name' columns regardless of row
    btGridCellClassCallback(row: any, col: GridColumn): string {
        if (col.name === 'name') {
            if (row.id() === 7) {
                return 'text-lowercase font-weight-bold text-info';
            }
            return 'text-uppercase font-weight-bold text-success';
        }
    }

    doPrint() {
        this.printer.print({
            template: this.printTemplate,
            contextData: {world : this.world},
            printContext: 'default'
        });

        this.printer.print({
            text: '<b>hello</b>',
            printContext: 'default'
        });
    }

    printWithDialog() {
        this.printer.print({
            template: this.printTemplate,
            contextData: {world : this.world},
            printContext: 'default',
            showDialog: true
        });
    }

    changeDate(date) {
        console.log('HERE WITH ' + date);
        this.testDate = date;
    }

    showProgress() {
        this.progressDialog.open();

        // every 250ms emit x*10 for 0-10
        observableTimer(0, 250).pipe(
            map(x => x * 10),
            take(11)
        ).subscribe(
            val => this.progressDialog.update({value: val, max: 100}),
            (err: unknown) => {},
            ()  => this.progressDialog.close()
        );
    }

    testToast() {
        this.toast.success('HELLO TOAST TEST');
        setTimeout(() => this.toast.danger('DANGER TEST AHHH!'), 4000);
    }

    testStrings() {
        this.strings.interpolate('staff.sandbox.test', {name : 'janey'})
            .then(txt => this.toast.success(txt));

        setTimeout(() => {
            this.strings.interpolate('staff.sandbox.test', {name : 'johnny'})
                .then(txt => this.toast.success(txt));
        }, 4000);
    }

    confirmNumber(num: number): void {
        this.numThings = num;
        console.log(this.numThings);
        this.numConfirmDialog.open();
    }

    showEditDialog(idlThing: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = idlThing['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: 'lg'}).subscribe(
                ok => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.acpGrid.reloadWithoutPagerReset();
                    resolve(ok);
                },
                (rejection: unknown) => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(rejection);
                }
            );
        });
    }

    allFutureDates(date: NgbDate, current: { year: number; month: number; }) {
        const currentTime = new Date();
        const today = new NgbDate(currentTime.getFullYear(), currentTime.getMonth() + 1, currentTime.getDate());
        return date.after(today);
    }

    sevenDaysAgo() {
        const d = new Date();
        d.setDate(d.getDate() - 7);
        return d;
    }

    testServerPrint() {

        // Note these values can be IDL objects or plain hashes.
        const templateData = {
            patron:  this.samples.listOfThings('au')[0],
            address: this.samples.listOfThings('aua')[0]
        };

        // NOTE: eventually this will be baked into the print service.
        this.printer.print({
            templateName: 'patron_address',
            contextData: templateData,
            printContext: 'default'
        });
    }

    openNote() {
        this.noteDialog.open()
            .subscribe(val => console.log('note value', val));
    }
}

