import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, Input, ViewChild, ElementRef} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridColumn, GridRowFlairEntry} from '@eg/share/grid/grid';
import {IdlObject} from '@eg/core/idl.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {LinkedCircLimitSetsComponent} from './linked-circ-limit-sets.component';
import {StringComponent} from '@eg/share/string/string.component';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    templateUrl: './circ-matrix-matchpoint.component.html'
})

export class CircMatrixMatchpointComponent implements OnInit {
    recId: number;
    gridDataSource: GridDataSource;
    initDone = false;
    dataSource: GridDataSource = new GridDataSource();
    showLinkLimitSets = false;
    usedSetLimitList = [];
    linkedLimitSets = [];
    limitSetNames = {};

    
    @ViewChild('limitSets', { static: false }) limitSets: ElementRef;
    @ViewChild('circLimitSets', { static: true }) limitSetsComponent: LinkedCircLimitSetsComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;

    @Input() idlClass = 'ccmm';
    // Default sort field, used when no grid sorting is applied.
    @Input() sortField: string;

    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    
    constructor(
        private pcrud: PcrudService,
        private toast: ToastService
    ) {
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.initDone = true;
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idlClass] = sort[0].name + ' ' + sort[0].dir;
            } else if (this.sortField) {
                // Default sort field
                orderBy[this.idlClass] = this.sortField;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };
            return this.pcrud.retrieveAll('ccmm', searchOps, {fleshSelectors: true});
        }
    }


    clearLinkedCircLimitSets() {
        this.limitSetsComponent.usedSetLimitList = [];
        this.limitSetsComponent.linkedSetList = [];
        this.linkedLimitSets = [];
    }

    showEditDialog(field: IdlObject): Promise<any> {
        this.limitSetsComponent.showLinkLimitSets = true;
        this.getLimitSets(field.id());
        this.editDialog.mode = 'update';
        this.editDialog.recordId = field['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                    resolve(result);
                },
                error => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
            const modalBody = document.getElementsByClassName("modal-body");
            modalBody[modalBody.length-1].appendChild(this.limitSets.nativeElement)
        })
    }

    editSelected(fields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (field: IdlObject) => {
            if (!field) { return; }
            this.showEditDialog(field).then(
                () => editOneThing(fields.shift()));
        };
        editOneThing(fields.shift());
    }

    createNew() {
        this.getLimitSets(null);
        this.limitSetsComponent.showLinkLimitSets = true;
        this.editDialog.mode = 'create';
        // We reuse the same editor for all actions.  Be sure
        // create action does not try to modify an existing record.
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.limitSetsComponent.showLinkLimitSets = false;
                this.grid.reload();
            },
            rejection => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
                this.limitSetsComponent.showLinkLimitSets = false;
            }
        );
        const modalBody = document.getElementsByClassName("modal-body");
        modalBody[modalBody.length-1].appendChild(this.limitSets.nativeElement)
    }

    setLimitSets(sets) {
        this.linkedLimitSets = sets;
    }

    /**
     * Runs through the different CRUD operations, specified by the object that is passed into each.
     * @param matchpoint 
     */
    configureLimitSets(matchpoint) {
        const linkedSets = this.linkedLimitSets;
        Object.keys(linkedSets).forEach((key) =>{
            let ls = linkedSets[key]
            if(ls.created) {
                this.deleteLimitSets(ls).then(()=>{
                    if (ls.isNew && !ls.isDeleted) {
                        this.pcrud.create(this.createLimitSets(ls.linkedLimitSet,matchpoint)).subscribe(() =>{})
                    } else if(!ls.isNew && !ls.isDeleted) {
                        this.updateLimitSets(ls.linkedLimitSet);
                    }
                })
            }
        })
    }

    getLimitSets(id) {
        this.pcrud.retrieveAll("ccmlsm").subscribe((res) =>{
            /**
             * If the limit set's matchpoint equals the matchpoint given
             * by the user, then add that to the set limit list
             */
            this.limitSetsComponent.usedSetLimitList.push(res.limit_set());
            if (res.matchpoint() == id) {
                this.limitSetsComponent.createFilledLimitSetObject(res)
            }
        })
        /**
         * Retrives all limit set names
         */
        this.pcrud.retrieveAll("ccls").subscribe(res =>{
            this.limitSetsComponent.limitSetNames[res.id()] = res.name();
        })
    }

    createLimitSets(limitSet,matchpoint) {
        if(typeof matchpoint == "number" || typeof matchpoint == "string") {
            limitSet.matchpoint(matchpoint)
        } else {
            limitSet.matchpoint(matchpoint.id())
        }
        return limitSet
    }

    updateLimitSets(limitSet) {
        this.pcrud.update(limitSet).subscribe(() =>{})
    }

    deleteLimitSets(limitSet) {
        return new Promise((resolve, reject) =>{
            if (limitSet.isDeleted) {
                if(limitSet.linkedLimitSet.id()) {
                    this.pcrud.remove(limitSet.linkedLimitSet).subscribe(res =>{
                        resolve();
                    })
                } else {
                    resolve();
                }
            } else {
                resolve();
            }
        })
    }
}

