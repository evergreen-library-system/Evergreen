/* eslint-disable */
import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, AfterViewInit, Input, ViewChild, ElementRef} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridColumn, GridRowFlairEntry} from '@eg/share/grid/grid';
import {ActivatedRoute} from '@angular/router';
import {Location} from '@angular/common';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {LinkedCircLimitSetsComponent} from './linked-circ-limit-sets.component';
import {CircMatrixMatchpointDialogComponent} from './circ-matrix-matchpoint-dialog.component';
import {StringComponent} from '@eg/share/string/string.component';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {OrgService} from '@eg/core/org.service';
import {OrgFamily} from '@eg/share/org-family-select/org-family-select.component';

  @Component({
      templateUrl: './circ-matrix-matchpoint.component.html'
  })
export class CircMatrixMatchpointComponent implements OnInit {
    recId: number;
    orgField = 'org_unit';
    disableOrgFilter = false;
    initDone = false;
    dataSource: GridDataSource;
    gridFilters: {[key: string]: string | number};
    showLinkLimitSets = false;
    usedSetLimitList = {};
    linkedLimitSets = [];
    limitSetNames = {};
    dividerStyle = {
        width: '30%',
        marginTop: '25px',
        marginLeft: '73%'
    };
    notOneSelectedRow: (rows: IdlObject[]) => boolean;

    @ViewChild('limitSets', { static: false }) limitSets: ElementRef;
    @ViewChild('circLimitSets', { static: true }) limitSetsComponent: LinkedCircLimitSetsComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('matchpointDialog', { static: true }) matchpointDialog: CircMatrixMatchpointDialogComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;

    @Input() idlClass = 'ccmm';
    // Default sort field, used when no grid sorting is applied.
    @Input() sortField: string;

    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    idlClassDef: any;
    pkeyField: string;
    contextOrg: IdlObject;
    searchOrgs: OrgFamily;
    orgFieldLabel: string;
    viewPerms: string;
    canCreate: boolean;

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private toast: ToastService,
        public idl: IdlService,
        private org: OrgService,
        public auth: AuthService,
        private perm: PermService
    ) {}

    ngOnInit() {
        this.initDone = true;
        this.notOneSelectedRow = (rows: IdlObject[]) => (rows.length !== 1);
        this.idlClassDef = this.idl.classes[this.idlClass];
        this.pkeyField = this.idlClassDef.pkey || 'id';

        // Limit the view org selector to orgs where the user has
        // permacrud-encoded view permissions.
        const pc = this.idlClassDef.permacrud;
        if (pc && pc.retrieve) {
            this.viewPerms = pc.retrieve.perms;
        }

        const contextOrg = this.route.snapshot.queryParamMap.get('contextOrg');
        this.checkCreatePerms();
        this.applyOrgValues(Number(contextOrg));

        this.initDataSource();
    }

    applyOrgValues(orgId?: number) {

        if (this.disableOrgFilter) {
            this.orgField = null;
            return;
        }

        if (!this.orgField) {
            // If no org unit field is specified, try to find one.
            // If an object type has multiple org unit fields, the
            // caller should specify one or disable org unit filter.
            this.idlClassDef.fields.forEach(field => {
                if (field['class'] === 'aou') {
                    this.orgField = field.name;
                }
            });
        }

        if (this.orgField) {
            this.orgFieldLabel = this.idlClassDef.field_map[this.orgField].label;
            this.contextOrg = this.org.get(orgId) || this.org.get(this.auth.user().ws_ou()) || this.org.root();
            this.searchOrgs = {primaryOrgId: this.contextOrg.id()};
        }
    }

    checkCreatePerms() {
        this.canCreate = false;
        const pc = this.idlClassDef.permacrud || {};
        const perms = pc.create ? pc.create.perms : [];
        if (perms.length === 0) { return; }

        this.perm.hasWorkPermAt(perms, true).then(permMap => {
            Object.keys(permMap).forEach(key => {
                if (permMap[key].length > 0) {
                    this.canCreate = true;
                }
            });
        });
    }

    initDataSource() {
        this.dataSource = new GridDataSource();

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

            if (!this.contextOrg && !this.gridFilters && !Object.keys(this.dataSource.filters).length) {
                // No org filter -- fetch all rows
                return this.pcrud.retrieveAll(
                    this.idlClass, searchOps, {fleshSelectors: true});
            }

            const search: any[] = new Array();
            const orgFilter: any = {};

            if (this.orgField && (this.searchOrgs || this.contextOrg)) {
                orgFilter[this.orgField] =
                    this.searchOrgs.orgIds || [this.contextOrg.id()];
                search.push(orgFilter);
            }

            Object.keys(this.dataSource.filters).forEach(key => {
                Object.keys(this.dataSource.filters[key]).forEach(key2 => {
                    search.push(this.dataSource.filters[key][key2]);
                });
            });

            // FIXME - do we want to remove this, which is used in several
            // secondary admin pages, in favor of switching it to the built-in
            // grid filtering?
            if (this.gridFilters) {
                // Lay the URL grid filters over our search object.
                Object.keys(this.gridFilters).forEach(key => {
                    const urlProvidedFilters = {};
                    urlProvidedFilters[key] = this.gridFilters[key];
                    search.push(urlProvidedFilters);
                });
            }

            return this.pcrud.search(
                this.idlClass, search, searchOps, {fleshSelectors: true});
        };
    }

    clearLinkedCircLimitSets() {
        console.debug('clearLinkedCircLimitSets',this.limitSetsComponent);
        this.limitSetsComponent.reset();
        this.linkedLimitSets = [];
    }

    closeDialog() {
        this.matchpointDialog.closeEditor();
        this.grid.reload();
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

    showEditDialog(field: IdlObject): Promise<any> {
        this.limitSetsComponent.showLinkLimitSets = true;
        this.getLimitSets(field.id());
        this.editDialog.mode = 'update';
        this.editDialog.recordId = field['id']();
        return new Promise((resolve, reject) => {
            this.matchpointDialog.open({size: this.dialogSize}).subscribe(
                result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                    resolve(result);
                },
                (error: unknown) => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    }

    createNew() {
        this.getLimitSets(null);
        this.limitSetsComponent.showLinkLimitSets = true;
        this.editDialog.mode = 'create';
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.handleRecordChange();
        // We reuse the same editor for all actions.  Be sure
        // create action does not try to modify an existing record.
        this.matchpointDialog.open({size: this.dialogSize}).subscribe(
            ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.limitSetsComponent.showLinkLimitSets = false;
                this.grid.reload();
            },
            (rejection: unknown) => {
                if (!(rejection as any).dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
                this.limitSetsComponent.showLinkLimitSets = false;
            }
        );
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
        Object.keys(linkedSets).forEach((key) => {
            const ls = linkedSets[key];
            if (ls.created) {
                this.deleteLimitSets(ls).then(() => {
                    if (ls.isNew && !ls.isDeleted) {
                        this.pcrud.create(this.createLimitSets(ls.linkedLimitSet, matchpoint)).subscribe(() => {});
                    } else if (!ls.isNew && !ls.isDeleted) {
                        this.updateLimitSets(ls.linkedLimitSet);
                    }
                });
            }
        });
    }

    getLimitSets(id) {
        this.clearLinkedCircLimitSets();
        this.pcrud.retrieveAll('ccmlsm').subscribe((res) => {
            /**
             * If the limit set's matchpoint equals the matchpoint given
             * by the user, then add that to the set limit list
             */
            this.limitSetsComponent.usedSetLimitList[res.limit_set()] = res.id();
            if (res.matchpoint() === id) {
                this.limitSetsComponent.createFilledLimitSetObject(res);
            }
        });
        /**
         * Retrives all limit set names
         */
        this.pcrud.retrieveAll('ccls').subscribe((res) => {
            this.limitSetsComponent.limitSetNames[res.id()] = res.name();
        });
    }

    createLimitSets(limitSet, matchpoint) {
        if (typeof matchpoint === 'number' || typeof matchpoint === 'string') {
            limitSet.matchpoint(matchpoint);
        } else {
            limitSet.matchpoint(matchpoint.id());
        }
        return limitSet;
    }

    updateLimitSets(limitSet) {
        this.pcrud.update(limitSet).subscribe(() => {});
    }

    deleteLimitSets(limitSet) {
        return new Promise<void>((resolve, reject) => {
            if (limitSet.isDeleted) {
                if (limitSet.linkedLimitSet.id()) {
                    this.pcrud.remove(limitSet.linkedLimitSet).subscribe(res => {
                        resolve();
                    });
                } else {
                    resolve();
                }
            } else {
                resolve();
            }
        });
    }
}
