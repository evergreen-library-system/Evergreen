import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Router} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';

@Component({
    templateUrl: './triggers.component.html'
})

export class TriggersComponent implements OnInit {

    eventsDataSource: GridDataSource = new GridDataSource();
    hooksDataSource: GridDataSource = new GridDataSource();
    reactorsDataSource: GridDataSource = new GridDataSource();
    validatorsDataSource: GridDataSource = new GridDataSource();
    triggerTab: 'eventDefinitions' | 'hooks' | 'reactors' | 'validators' = 'eventDefinitions';
    idlClass: string;

    @ViewChild('eventDialog', {static: false}) eventDialog: FmRecordEditorComponent;
    @ViewChild('hookDialog', {static: false}) hookDialog: FmRecordEditorComponent;
    @ViewChild('reactorDialog', {static: false}) reactorDialog: FmRecordEditorComponent;
    @ViewChild('validatorDialog', {static: false}) validatorDialog: FmRecordEditorComponent;

    @ViewChild('confirmDialog', {static: false}) private confirmDialog: ConfirmDialogComponent;

    @ViewChild('eventsGrid', {static: false}) eventsGrid: GridComponent;
    @ViewChild('hooksGrid', {static: false}) hooksGrid: GridComponent;
    @ViewChild('reactorsGrid', {static: false}) reactorsGrid: GridComponent;
    @ViewChild('validatorsGrid', {static: false}) validatorsGrid: GridComponent;

    @ViewChild('updateSuccessString', {static: false}) updateSuccessString: StringComponent;
    @ViewChild('updateFailedString', {static: false}) updateFailedString: StringComponent;
    @ViewChild('cloneSuccessString', {static: false}) cloneSuccessString: StringComponent;
    @ViewChild('cloneFailedString', {static: false}) cloneFailedString: StringComponent;
    @ViewChild('deleteFailedString', {static: false}) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', {static: false}) deleteSuccessString: StringComponent;
    @ViewChild('createSuccessString', {static: false}) createSuccessString: StringComponent;
    @ViewChild('createErrString', {static: false}) createErrString: StringComponent;

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private toast: ToastService,
        private router: Router,
    ) {
    }

    ngOnInit() {
        this.eventsDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderEventsBy: any = {atevdef: 'name'};
            if (sort.length) {
                orderEventsBy.atevdef = sort[0].name + ' ' + sort[0].dir;
            }
            return this.getData('atevdef', orderEventsBy, this.eventsDataSource, pager);
        };

        this.hooksDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderHooksBy: any = {ath: 'key'};
            if (sort.length) {
                orderHooksBy.ath = sort[0].name + ' ' + sort[0].dir;
            }
            return this.getData('ath', orderHooksBy, this.hooksDataSource, pager);
        };

        this.reactorsDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderReactorsBy: any = {atreact: 'module'};
            if (sort.length) {
                orderReactorsBy.atreact = sort[0].name + ' ' + sort[0].dir;
            }
            return this.getData('atreact', orderReactorsBy, this.reactorsDataSource, pager);
        };

        this.validatorsDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderValidatorsBy: any = {atval: 'module'};
            if (sort.length) {
                orderValidatorsBy.atval = sort[0].name + ' ' + sort[0].dir;
            }
            return this.getData('atval', orderValidatorsBy, this.validatorsDataSource, pager);
        };
    }

    getData(idlString: any, currentOrderBy: any, currentDataSource: any, pager: Pager) {
        const base: Object = {};
        base[this.idl.classes[idlString].pkey] = {'!=' : null};
        const query: any = new Array();
        query.push(base);
        Object.keys(currentDataSource.filters).forEach(key => {
            Object.keys(currentDataSource.filters[key]).forEach(key2 => {
                query.push(currentDataSource.filters[key][key2]);
            });
        });
        return this.pcrud.search(idlString,
            query, {
                offset: pager.offset,
                limit: pager.limit,
                order_by: currentOrderBy
            });
    }

    onTabChange(event: NgbNavChangeEvent) {
        this.triggerTab = event.nextId;
    }

    createNewEvent = () => {
        this.createNewThing(this.eventDialog, this.eventsGrid);
    };

    createNewHook = () => {
        this.createNewThing(this.hookDialog, this.hooksGrid);
    };

    createNewReactor = () => {
        this.createNewThing(this.reactorDialog, this.reactorsGrid);
    };

    createNewValidator = () => {
        this.createNewThing(this.validatorDialog, this.validatorsGrid);
    };

    createNewThing = (currentDialog: any, currentGrid: any) => {
        currentDialog.mode = 'create';
        currentDialog.recordId = null;
        currentDialog.record = null;
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

    editSelected = (selectedRecords: IdlObject[]) => {
        if (this.triggerTab === 'eventDefinitions') {
            this.editEventDefinition(selectedRecords);
            return;
        }
        const editOneThing = (record: IdlObject) => {
            if (!record) { return; }
            this.showEditDialog(record).then(
                () => editOneThing(selectedRecords.shift()));
        };
        editOneThing(selectedRecords.shift());
    };

    editEventDefinition = (selectedRecords: IdlObject[]) => {
        const id = selectedRecords[0].id();
        this.router.navigate(['/staff/admin/local/action_trigger/event_definition/' + id]);
    };

    lookUpIdl (idl: string) {
        let currentDialog;
        let currentGrid;
        switch (idl) {
            case 'atevdef':
                currentDialog = this.eventDialog;
                currentGrid = this.eventsGrid;
                break;
            case 'ath':
                currentDialog = this.hookDialog;
                currentGrid = this.hooksGrid;
                break;
            case 'atreact':
                currentDialog = this.reactorDialog;
                currentGrid = this.reactorsGrid;
                break;
            case 'atval':
                currentDialog = this.validatorDialog;
                currentGrid = this.validatorsGrid;
                break;
            default:
                console.debug('Unknown class name');
        }
        return {currentDialog: currentDialog, currentGrid: currentGrid};
    }

    showEditDialog = (selectedRecord: IdlObject): Promise<any> => {
        const idl = selectedRecord.classname;
        const lookupResults = this.lookUpIdl(idl);
        const currentDialog = lookupResults.currentDialog;
        const currentGrid = lookupResults.currentGrid;
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

    deleteSelected = (idlThings: IdlObject[]) => {
        const idl = idlThings[0].classname;
        const currentGrid = this.lookUpIdl(idl).currentGrid;
        idlThings.forEach(idlThing => idlThing.isdeleted(true));
        this.pcrud.autoApply(idlThings).subscribe(
            { next: val => {
                console.debug('deleted: ' + val);
                this.deleteSuccessString.current()
                    .then(str => this.toast.success(str));
                currentGrid.reload();
            }, error: (err: unknown) => {
                this.deleteFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    };

    cloneSelected = (selectedRecords: IdlObject[]) => {
        const clone = this.idl.clone(selectedRecords[0]);
        // look for existing environments
        this.pcrud.search('atenv', {event_def: selectedRecords[0].id()}, {}, {atomic: true})
            .toPromise().then(envs => {
                if (envs) {
                // if environments found, ask user if they want to clone them
                    this.confirmDialog.open().toPromise().then(ok => {
                        if (ok) {
                            this.doClone(clone, envs);
                        } else {
                            this.doClone(clone, []);
                        }
                    });
                } else {
                    this.doClone(clone, []);
                }
            });
    };

    doClone(eventDef, env_list) {
        eventDef.id(null);
        eventDef.owner(null);
        this.eventDialog.mode = 'create';
        this.eventDialog.recordId = null;
        this.eventDialog.record = eventDef;
        this.eventDialog.open({size: 'lg'}).subscribe(
            { next: response => {
                this.cloneSuccessString.current()
                    .then(str => this.toast.success(str));
                this.eventsGrid.reload();
                // clone environments also if user previously confirmed
                if (env_list.length) {
                    this.cloneEnvs(response.id(), env_list);
                }
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.cloneFailedString.current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    }

    cloneEnvs(cloneId, env_list) {
        env_list.forEach(env => {
            env.event_def(cloneId);
            env.id(null);
        });
        this.pcrud.create(env_list).toPromise().then(
            ok => { },
            err => {
                this.cloneFailedString.current()
                    .then(str => this.toast.danger(str));
            }
        );
    }

}
