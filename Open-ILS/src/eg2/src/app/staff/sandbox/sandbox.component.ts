
import {timer as observableTimer, Observable, of} from 'rxjs';
import {Component, OnInit, ViewChild, Input, TemplateRef} from '@angular/core';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringService} from '@eg/share/string/string.service';
import {map, take} from 'rxjs/operators';
import {GridDataSource, GridColumn, GridRowFlairEntry} from '@eg/share/grid/grid';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {Pager} from '@eg/share/util/pager';
import {DateSelectComponent} from '@eg/share/date-select/date-select.component';
import {PrintService} from '@eg/share/print/print.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {FormatService} from '@eg/core/format.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {FormGroup, FormControl} from '@angular/forms';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
  templateUrl: 'sandbox.component.html'
})
export class SandboxComponent implements OnInit {

    @ViewChild('progressDialog')
    private progressDialog: ProgressDialogComponent;

    @ViewChild('dateSelect')
    private dateSelector: DateSelectComponent;

    @ViewChild('printTemplate')
    private printTemplate: TemplateRef<any>;

    @ViewChild('fmRecordEditor')
    private fmRecordEditor: FmRecordEditorComponent;

    @ViewChild('numConfirmDialog')
    private numConfirmDialog: ConfirmDialogComponent;

    public numThings = 0;

    // @ViewChild('helloStr') private helloStr: StringComponent;

    gridDataSource: GridDataSource = new GridDataSource();

    cbEntries: ComboboxEntry[];
    // supplier of async combobox data
    cbAsyncSource: (term: string) => Observable<ComboboxEntry>;

    btSource: GridDataSource = new GridDataSource();
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

    complimentEvergreen: (rows: IdlObject[]) => void;
    notOneSelectedRow: (rows: IdlObject[]) => boolean;

    // selector field value on metarecord object
    aMetarecord: string;

    // cross-tab communications example
    private sbChannel: any;
    sbChannelText: string;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private strings: StringService,
        private toast: ToastService,
        private format: FormatService,
        private printer: PrintService
    ) {
        // BroadcastChannel is not yet defined in PhantomJS and elsewhere
        this.sbChannel = (typeof BroadcastChannel === 'undefined') ?
            {} : new BroadcastChannel('eg.sbChannel');
        this.sbChannel.onmessage = (e) => this.sbChannelHandler(e);
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

        this.badOrgForm.get('badOrgSelector').valueChanges.subscribe(bad => {
            this.toast.danger('The fanciest libraries are: ' + JSON.stringify(bad.orgIds));
        });

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
    }

    sbChannelHandler = msg => {
        setTimeout(() => { this.sbChannelText = msg.data.msg; });
    }

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
            err => console.error(err),
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
            err => {},
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

}


