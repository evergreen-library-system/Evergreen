import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {ActivatedRoute, Router} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';

@Component({
    templateUrl: './trigger-edit.component.html'
})

export class EditEventDefinitionComponent implements OnInit {

    evtDefId: number;
    evtDefName: String;
    evtReactor: string;
    evtAltEligible: Boolean = false;

    testErr1: String = '';
    testErr2: String = '';
    testResult: String = '';
    testDone: Boolean = false;

    altTemplateDataSource: GridDataSource = new GridDataSource();
    envDataSource: GridDataSource = new GridDataSource();
    paramDataSource: GridDataSource = new GridDataSource();

    editTab: 'def' | 'alt' | 'env' | 'param' | 'test' = 'def';

    @ViewChild('paramDialog') paramDialog: FmRecordEditorComponent;
    @ViewChild('envDialog') envDialog: FmRecordEditorComponent;
    @ViewChild('altTemplateDialog') altTemplateDialog: FmRecordEditorComponent;

    @ViewChild('envGrid') envGrid: GridComponent;
    @ViewChild('paramGrid') paramGrid: GridComponent;
    @ViewChild('altTemplateGrid') altTemplateGrid: GridComponent;

    @ViewChild('updateSuccessString') updateSuccessString: StringComponent;
    @ViewChild('updateFailedString') updateFailedString: StringComponent;
    @ViewChild('cloneSuccessString') cloneSuccessString: StringComponent;
    @ViewChild('cloneFailedString') cloneFailedString: StringComponent;
    @ViewChild('deleteFailedString') deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString') deleteSuccessString: StringComponent;
    @ViewChild('createSuccessString') createSuccessString: StringComponent;
    @ViewChild('createErrString') createErrString: StringComponent;
    @ViewChild('eventDuringTestString') eventDuringTestString: StringComponent;
    @ViewChild('errorDuringTestString') errorDuringTestString: StringComponent;

    constructor(
        private router: Router,
        private idl: IdlService,
        private pcrud: PcrudService,
        private toast: ToastService,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
    ) {
    }

    ngOnInit() {
        this.evtDefId = parseInt(this.route.snapshot.paramMap.get('id'), 10);

        // get current event def name to display on the banner
        this.pcrud.search('atevdef',
            {id: this.evtDefId}, {}).toPromise().then(rec => {
            this.evtDefName = rec.name();
        });

        // get current event def reactor to decide if the alt template tab should show
        this.pcrud.search('atevdef',
            {id: this.evtDefId}, {}).toPromise().then(rec => {
            this.evtReactor = rec.reactor();
            if ('ProcessTemplate SendEmail SendSMS'.indexOf(this.evtReactor) > -1) { this.evtAltEligible = true; }
        });

        this.envDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.pcrud.search('atenv',
                {event_def: this.evtDefId}, {});
        };

        this.altTemplateDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.pcrud.search('atevalt',
                {event_def: this.evtDefId}, {});
        };

        this.paramDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.pcrud.search('atevparam',
                {event_def: this.evtDefId}, {});
        };
    }

    onTabChange(event: NgbNavChangeEvent) {
        this.editTab = event.nextId;
    }

    createNewEnv = () => {
        this.createNewThing(this.envDialog, this.envGrid, 'atenv');
    };

    createNewAltTemplate = () => {
        this.createNewThing(this.altTemplateDialog, this.altTemplateGrid, 'atevalt');
    };

    createNewParam = () => {
        this.createNewThing(this.paramDialog, this.paramGrid, 'atevparam');
    };

    createNewThing = (currentDialog: any, currentGrid: any, idl: any) => {
        currentDialog.mode = 'create';
        currentDialog.recordId = null;
        const newRecord = this.idl.create(idl);
        newRecord.event_def(this.evtDefId);
        currentDialog.mode = 'create';
        currentDialog.record = newRecord;
        currentDialog.open({size: 'lg'}).subscribe(
            ok => {
                this.createSuccessString.current()
                    .then(str => this.toast.success(str));
                currentGrid.reload();
            },
            rejection => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            }
        );
    };

    deleteSelected = (idlThings: IdlObject[]) => {
        let currentGrid;
        if (idlThings[0].classname === 'atenv') {
            currentGrid = this.envGrid;
        } else if (idlThings[0].classname === 'atevalt') {
            currentGrid = this.altTemplateGrid;
        } else {
            currentGrid = this.paramGrid;
        }
        idlThings.forEach(idlThing => idlThing.isdeleted(true));
        let _deleted = 0;
        this.pcrud.autoApply(idlThings).subscribe(
            { next: val => {
                console.debug('deleted: ' + val);
                this.deleteSuccessString.current()
                    .then(str => this.toast.success(str));
                _deleted++;
            }, error: (err: unknown) => {
                this.deleteFailedString.current()
                    .then(str => this.toast.danger(str));
            }, complete: () => {
                if (_deleted > 0) {
                    currentGrid.reload();
                }
            } }
        );
    };

    editSelected = (selectedRecords: IdlObject[]) => {
        const editOneThing = (record: IdlObject) => {
            if (!record) { return; }
            this.showEditDialog(record).then(
                () => editOneThing(selectedRecords.shift()));
        };
        editOneThing(selectedRecords.shift());
    };

    showEditDialog = (selectedRecord: IdlObject): Promise<any> => {
        let currentDialog;
        let currentGrid;
        if (selectedRecord.classname === 'atenv') {
            currentDialog = this.envDialog;
            currentGrid = this.envGrid;
        } else if (selectedRecord.classname === 'atevalt') {
            currentDialog = this.altTemplateDialog;
            currentGrid = this.altTemplateGrid;
        } else {
            currentDialog = this.paramDialog;
            currentGrid = this.paramGrid;
        }
        currentDialog.mode = 'update';
        const clone = this.idl.clone(selectedRecord);
        currentDialog.record = clone;
        return new Promise((resolve, reject) => {
            currentDialog.open({size: 'lg'}).subscribe(
                result => {
                    this.updateSuccessString.current()
                        .then(str => this.toast.success(str));
                    currentGrid.reload();
                    resolve(result);
                },
                error => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    };

    runTest = (barcode) => {
        if (!barcode) {
            return;
        }
        this.clearTestResults();
        this.net.request(
            'open-ils.circ', 'open-ils.circ.trigger_event_by_def_and_barcode.fire',
            this.auth.token(), this.evtDefId, barcode
        ).subscribe({ next: res => {
            this.testDone = true;
            if (res.ilsevent) {
                this.eventDuringTestString.current({ ilsevent: res.ilsevent, textcode : res.textcode})
                    .then(str => this.testErr1 = str);
                this.testErr2 = res.desc;
            } else {
                this.testResult = res.template_output().data();
            }

        }, error: (err: any) => {
            this.testDone = true;
            this.errorDuringTestString.current().then(str => this.testErr1 = str);
            this.testErr2 = err;
        } });
    };

    clearTestResults = () => {
        this.testDone = false;
        this.testErr1 = '';
        this.testErr2 = '';
        this.testResult = '';
    };
    back = () => {
        this.router.navigate(['/staff/admin/local/action_trigger/event_definition/']);
    };
}
