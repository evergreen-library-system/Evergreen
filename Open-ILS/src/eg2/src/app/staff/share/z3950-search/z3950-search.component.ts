import {Component, ViewChild, OnInit, Input, TemplateRef, Directive, AfterViewInit, ElementRef} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {FormBuilder, FormGroup, FormControl, Validators, FormArray} from '@angular/forms';
import {map, mergeMap, defaultIfEmpty, last} from 'rxjs/operators';
import {EMPTY, Observable, of, from, finalize} from 'rxjs';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {StoreService} from '@eg/core/store.service';
import {Z3950SearchService} from './z3950.service';
import {EventService} from '@eg/core/event.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';

@Component({
    selector: 'eg-z3950-search',
    styleUrls: ['z3950-search.component.css'],
    templateUrl: 'z3950-search.component.html'
})

export class Z3950SearchComponent implements OnInit {
    static domId = 0;

    cellTextGenerator: GridCellTextGenerator;
    gridSource: GridDataSource;
    @ViewChild('ResultGrid', { static: true }) resultGrid: GridComponent;
    @ViewChild('confirmImportDlg', { static: false }) confirmImportDialog: ConfirmDialogComponent;
    @ViewChild('showMARCtmpl', { static: true }) showMARCTemplate: TemplateRef<any>;
    @ViewChild('showMARCdlg', { static: false }) showMARCDialog: ConfirmDialogComponent;
    @ViewChild('editMARCtmpl', { static: true }) editMARCTemplate: TemplateRef<any>;
    @ViewChild('editMARCdlg', { static: false }) editMARCDialog: ConfirmDialogComponent;
    @ViewChild('addToSLtmpl', { static: true }) addToSLTemplate: TemplateRef<any>;
    @ViewChild('addToSLdlg', { static: false }) addToSLDialog: ConfirmDialogComponent;
    @ViewChild('addToPOtmpl', { static: true }) addToPOTemplate: TemplateRef<any>;
    @ViewChild('addToPOdlg', { static: false }) addToPODialog: ConfirmDialogComponent;
    @ViewChild('jumpToSLDlg', { static: false }) jumpToSL: ConfirmDialogComponent;
    @ViewChild('jumpToPODlg', { static: false }) jumpToPO: ConfirmDialogComponent;
    @ViewChild('overlayMARCtmpl', { static: true }) overlayMARCTemplate: TemplateRef<any>;
    @ViewChild('overlayMARCdlg', { static: false }) overlayMARCDialog: ConfirmDialogComponent;
    @ViewChild('rawSearchPrmpt', { static: false }) rawSearchPrompt: PromptDialogComponent;

    @Input() searchMode = 'cat';
    @Input() persistKeyPrefix = 'global';
    @Input() includeNativeCatalog= true;
    @Input() showForm = true; // display search form by default
    // ID to display in the DOM for this search component
    @Input() domId = 'eg-z3950-search-' + Z3950SearchComponent.domId++;

    _permittedTargets: any[] = [];
    total_hits = 0;
    bib_sources: IdlObject[] = [];
    field_strip_groups = [];

    currentFields = [];
    searchInProgress = false;
    rawSearch = '';
    _fromRaw = false;

    overlayTarget: number = null;
    overlayTargetTCN = '';
    defaultField = '';
    currentEditRecord: any = null;
    currentEditAction = '';
    currentEditConfirm = '';
    currentEditHideFooter = false;
    currentEditFastItem: any = null;

    selectedOverlayProfile: number = null;

    currentTargetSL: number = null;
    currentTargetPO: number = null;
    currentNewPOprepayment_required = false;
    currentNewPOprovider: number = null;
    currentNewPOordering_agency: number = null;

    selectedSL: ComboboxEntry = null;
    selectedPO: ComboboxEntry = null;

    showMARCRecordSet: any[] = [];
    lastImportedRecord: number = null;

    get_tcn(currTarget) {
        return this.pcrud.retrieve('bre', currTarget, {
            select: {bre: ['tcn_value']}
        }).toPromise().then(function(rec) {
            return rec.tcn_value();
        });
    }

    constructor(
        private route: ActivatedRoute,
        private holdings: HoldingsService,
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private store: StoreService,
        private zService: Z3950SearchService,
        private evt: EventService,
        private auth: AuthService
    ) {

        this.overlayTarget = this.store.getLocalItem('eg.cat.marked_overlay_record');
        if (this.overlayTarget) {
            this.get_tcn(this.overlayTarget).then( t => this.overlayTargetTCN = t );
        }

        this.zService.fetchDefaultField().then( d => this.defaultField = d || 'isbn');
        this.zService.loadTargets().then(_ => this.currentFields = this.fieldsGroupedByNameForSelectedTargets());


        this.pcrud.search('vibtg',
            {
                always_apply : 'f',
                owner : {
                    'in' : {
                        select : {
                            aou : [{
                                column : 'id',
                                transform : 'actor.org_unit_ancestors',
                                result_field : 'id'
                            }]
                        },
                        from : 'aou',
                        where : {
                            id : this.auth.user().ws_ou()
                        }
                    }
                }
            },
            { order_by : { vibtq : ['label'] } }
        ).subscribe(strip_group => {
            strip_group.selected = false;
            this.field_strip_groups.push(strip_group);
        });
    }

    ngOnInit() {

        this.route.data.subscribe(data => {
            if (data && data.searchMode) {
                this.searchMode = data.searchMode;
            }
        });

        this.pcrud.retrieveAll('cbs', {}, {atomic : true})
            .pipe(map(l => this.bib_sources = l));

        this.gridSource = new GridDataSource();

        this.gridSource.getRows = (pager: Pager, sort: any): Observable<any> => {

            const query = this.currentQuery();
            if (!query.raw_search && Object.keys(query.search).length == 0) {
                return EMPTY;
            }

            let method = 'open-ils.search.z3950.search_class';

            if (this._fromRaw && query.raw_search) {
                method = 'open-ils.search.z3950.search_service';
                this._fromRaw = false;
                query['query'] = query.raw_search;
                delete query.search;
                delete query.raw_search;
                query.service = query.service[0];
                query.username = query.username[0];
                query.password = query.password[0];
            }

            query['limit'] = pager.limit;
            query['offset'] = pager.offset;

            let resultIndex = pager.offset;
            this.total_hits = 0;
            this.searchInProgress = true;

            return this.net.request(
                'open-ils.search',
                method,
                this.auth.token(),
                query
            ).pipe(mergeMap( result => {
                // FIXME when the search offset is > 0, the
                // total hits count can be wrong if one of the
                // Z39.50 targets has fewer than $offset hits; in that
                // case, result.count is not supplied.
                this.total_hits += (result.count || 0);

                const service_name = this
                    .zService
                    .targets
                    .find(t => t.code === result.service)
                    ?.settings
                    ?.label;

                return from(result.records.map( r => {
                    if (r.bibid) {
                        this.get_tcn(r.bibid).then(tcn => r.mvr['bibtcn'] = tcn);
                    }
                    r.mvr['bibid'] = r.bibid;
                    r.mvr['marcxml'] = r.marcxml;
                    r.mvr['service'] = result.service;
                    r.mvr['service_name'] = service_name;
                    r.mvr['index'] = resultIndex++;
                    return r.mvr;
                })).pipe(finalize(() => this.searchInProgress = false));
            }));
        };

        this.cellTextGenerator = {};
    }

    changeSelectedOrderingAgency($event) {
        this.currentNewPOordering_agency = $event ? $event.id : null;
    }

    changeSelectedProvider($event) {
        this.currentNewPOprovider = $event ? $event.id : null;
    }

    get_bibsrc_name_from_id(bs_id: any){
        if (!bs_id) {return null;}
        const bs = this.bib_sources.find(s => s.id() == bs_id ); // not sure if we'll get a number or a string, == is intentional
        return (bs ? bs.source() : null);
    }

    selectedFieldStripGroups() {
        return this.field_strip_groups.filter(grp => grp.selected).map(grp => grp.id());
    }

    import(rows: any) { // only one allowed!
        console.debug(`import: attempting to import ${rows.length} records (only the first will happen)`);
        return this.importOne(rows[0]);
    }

    importOne(r: any) { // only one allowed!
        console.debug('importOne: importing ', r);
        return this.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record.xml.import',
            this.auth.token(),
            r.marcxml,
            this.get_bibsrc_name_from_id(r.bibSource),
            null,
            null,
            this.selectedFieldStripGroups()
        ).subscribe(result => {
            console.debug('importOne: got result ', result);
            const evt = this.evt.parse(result);
            if (evt) {
                if (evt.textcode == 'TCN_EXISTS') {
                    this.toast.danger($localize`A record already exists with the requested TCN value`);
                } else {
                    this.toast.warning($localize`An unexpected error occurred`);
                }
            } else {
                this.lastImportedRecord = result.id();
                if (this.currentEditFastItem) {
                    const fastItem = this.currentEditFastItem;
                    this.currentEditFastItem = null;
                    this.holdings.spawnAddHoldingsUi(this.lastImportedRecord, null, [fastItem]);
                }

                this.confirmImportDialog.open().subscribe(
                    c => {
                        if (c) {window.open('/eg2/staff/catalog/record/' + this.lastImportedRecord, '_blank');}
                    },
                    (e: unknown) => {
                        this.toast.warning($localize`An unexpected error occurred`);
                    },
                    () => this.confirmImportDialog.close()
                );
            }

            return of();
        });
    }

    fieldLabelByName(n) {
        return this.currentFields.find(f => f.name === n).labels[0];
    }

    viewMARC(rows) {
        this.showMARCRecordSet = rows;
        this.showMARCDialog.open({size: 'xl', scrollable: true}).subscribe(_ => this.showMARCDialog.close());
    }

    editSelectedInSeries() {
        const self = this;
        const list_copy = [].concat(this.selectedRows());

        function nextOne () { // closure over self=this, list_copy=rows
            if (list_copy.length) {
                self.currentEditRecord = list_copy.shift();
                self.currentEditConfirm = list_copy.length ? $localize`Next` : $localize`Done`;
                setTimeout(() => self.editThenAction(nextOne));
            }
        }

        this.currentEditRecord = list_copy.shift();
        this.currentEditConfirm = list_copy.length ? $localize`Next` : $localize`Done`;
        this.editThenAction(nextOne);
    }

    addToSL(rows) {
        this.addToSLDialog.open({}).subscribe(c => {
            if (c) { // maybe create, then add record
                this.saveManualSL()
                    .then(ok => {
                        if (ok) {
                            this.createLineitems(rows.map(r => r.marcxml));
                            this.toast.success($localize`Added ${rows.length} records to selection list`);
                            this.addToSLDialog.close();
                            this.jumpToSL.open({}).subscribe(j => {
                                if (j) {window.open('/eg2/staff/acq/picklist/' + this.currentTargetSL, '_blank');}
                                this.jumpToSL.close();
                            });
                        }
                    });
            }
        });
    }

    saveManualSL(): Promise<boolean> {
        if (this.currentTargetSL) { return Promise.resolve(true); }
        if (!this.selectedSL) { return Promise.resolve(false); }

        if (!this.selectedSL.freetext) {
            // An existing PL was selected
            this.currentTargetSL = this.selectedSL.id;
            return Promise.resolve(true);
        }

        const sl = this.idl.create('acqpl');
        sl.name(this.selectedSL.label);
        sl.owner(this.auth.user().id());

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.picklist.create', this.auth.token(), sl).toPromise()

            .then(slId => {
                const evt = this.evt.parse(slId);
                if (evt) { alert(evt); return false; }
                this.currentTargetSL = slId;
                this.currentTargetPO = null;
                this.selectedSL = null;
                return true;
            });
    }

    addToPO(rows) {
        this.addToPODialog.open({size: 'lg'}).subscribe(c => {
            if (c) { // maybe create, then add record
                this.saveManualPO()
                    .then(ok => {
                        if (ok) {
                            this.createLineitems(rows.map(r => r.marcxml));
                            this.toast.success($localize`Added ${rows.length} records to purchase order`);
                            this.addToPODialog.close();
                            this.jumpToPO.open({}).subscribe(j => {
                                if (j) {window.open('/eg2/staff/acq/po/' + this.currentTargetPO, '_blank');}
                                this.jumpToPO.close();
                            });
                        }
                    });
            }
        });
    }

    saveManualPO(): Promise<boolean> {
        if (this.currentTargetPO) { return Promise.resolve(true); }

        if (this.selectedPO?.id) {
            // An existing PO was selected
            this.currentTargetPO = this.selectedPO.id;
            return Promise.resolve(true);
        }

        const po = this.idl.create('acqpo');
        po.name(this.selectedPO?.label || '');
        po.prepayment_required(this.currentNewPOprepayment_required);
        po.provider(this.currentNewPOprovider);
        po.ordering_agency(this.currentNewPOordering_agency || this.auth.user().ws_ou());


        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.purchase_order.create',
            this.auth.token(), po
        ).toPromise().then(resp => {
            if (resp && resp.purchase_order) {
                this.currentTargetPO = resp.purchase_order.id();
                this.currentTargetSL = null;
                this.selectedPO = null;
                return true;
            }
            return false;
        });
    }

    createLineitems(xml_list:string[]) {

        xml_list.forEach(xml => {
            const li = this.idl.create('jub');
            li.marc(xml);

            if (this.currentTargetSL) {
                li.picklist(this.currentTargetSL);
            } else if (this.currentTargetPO) {
                li.purchase_order(this.currentTargetPO);
            }

            li.selector(this.auth.user().id());
            li.creator(this.auth.user().id());
            li.editor(this.auth.user().id());

            this.net.request('open-ils.acq',
                'open-ils.acq.lineitem.create', this.auth.token(), li
            ).toPromise().then(liId => {

                const evt = this.evt.parse(liId);
                if (evt) { alert(evt); return; }

                /* probably not doing this redirection...
                this.liService.activateStateChange.emit();

                if (this.selectedPl) {
                    // Brief record was added to a picklist that is not
                    // currently focused in the UI.  Jump to it.
                    const url = `/staff/acq/picklist/${this.targetPicklist}`;
                    this.router.navigate([url], {fragment: liId});
                } else {

                    this.router.navigate(['../'], {
                        relativeTo: this.route,
                        queryParamsHandling: 'merge'
                    });
                }
                */

            });
        });
    }

    updateCurrentEditRecord(saveEvent) {
        this.currentEditRecord.marcxml = saveEvent.marcXml;
        this.currentEditRecord['bibSource'] = saveEvent.bibSource;

        if (saveEvent.fastItem?.fast_add) {
            this.currentEditFastItem = {...saveEvent.fastItem};
        } else {
            this.currentEditFastItem = null;
        }

        console.debug('record edit save event update currentEditRecord: ', this.currentEditRecord);
        if (this.currentEditHideFooter) {this.editMARCDialog.close();} // footer has the go/cancel buttons, close on MARC save
    }

    editThenImport(rows) {
        this.currentEditAction = $localize`Import`;
        this.currentEditConfirm = $localize`Import Record`;
        this.currentEditHideFooter = false;
        this.currentEditRecord = rows[0];
        this.editThenAction( () => this.importOne(this.currentEditRecord) );
    }

    justEditCurrent() {
        this.editThenAction(null);
    }

    editThenAction(cb:any) {
        const old_xml = this.currentEditRecord.marcxml;

        this.editMARCDialog.open(
            {size: 'xl', scrollable: true}
        ).subscribe(go => {
            this.editMARCDialog.close();

            if (go) {
                console.debug('now we will perform a callback action for:', this.currentEditRecord);
                if (cb) {cb();}
            } else {
                console.debug('we will NOT retain ', this.currentEditRecord);
                console.debug('rolling back to ', old_xml);
                this.currentEditRecord['bibSource'] = null;
                this.currentEditRecord.marcxml = old_xml;
            }
        });
    }

    cant_overlay() {
        if (!this.overlayTarget) {return true;}

        const rows = this.selectedRows();
        if (rows.length != 1) {return true;}
        if (rows[0]['service'] == 'native-evergreen-catalog'
            && rows[0]['bibid'] == this.overlayTarget
        ) {
            return true;
        }
        return false;
    }

    editThenOverlay(rows) {
        if (rows.length == 0 || !this.overlayTarget) {return;}

        // These are actually for the editor modal that may be triggered from the overlay modal :(
        this.currentEditAction = $localize`Overlay`;
        this.currentEditConfirm = $localize`Save Changes`;
        this.currentEditHideFooter = true;
        this.currentEditRecord = rows[0];

        const old_xml = this.currentEditRecord.marcxml;

        this.overlayMARCDialog.open(
            {size: 'xl', scrollable: true}
        ).subscribe(go => {
            this.overlayMARCDialog.close();

            if (go) {
                console.debug('now we merge and overlay with ', this.currentEditRecord);
                if (this.selectedOverlayProfile) {
                    this.mergeCurrentEditIntoTarget()
                        .subscribe(merged => this.overlayTargetedWithXML(merged));
                } else {
                    this.overlayTargetedWithXML(this.currentEditRecord.marcxml);
                }
            } else {
                console.debug('we will NOT overlay with ', this.currentEditRecord);
                console.debug('rolling back to ', old_xml);
                this.currentEditRecord.bibSource = null;
                this.currentEditRecord.marcxml = old_xml;
                this.selectedOverlayProfile = null;
            }
        });
    }

    mergeCurrentEditIntoTarget() {

        if (!this.selectedOverlayProfile) {return of();}
        if (!this.overlayTarget) {return of();}
        if (!this.currentEditRecord.marcxml) {return of();}

        return this.pcrud.retrieve('bre', this.overlayTarget).pipe(mergeMap(rec =>
            this.net.request(
                'open-ils.cat', 'open-ils.cat.merge.marc.per_profile',
                this.auth.token(), this.selectedOverlayProfile,
                [ rec.marc(), this.currentEditRecord.marcxml ]
            )
        ));
    }

    overlayTargetedWithXML(mxml: string) {
        console.debug(`overlayTargetedWithXML: overlaying ${this.overlayTarget} with `, mxml);

        return this.net.request(
            'open-ils.cat', 'open-ils.cat.biblio.record.marc.replace',
            this.auth.token(), this.overlayTarget, mxml,
            this.get_bibsrc_name_from_id(this.currentEditRecord.bibSource),
            null, this.selectedFieldStripGroups()
        ).subscribe(result  => {
            const previous_target = this.overlayTarget;
            this.overlayTarget = null;
            this.overlayTargetTCN = '';
            this.selectedOverlayProfile = null;
            console.debug('overlay complete');
            if (previous_target == this.store.getLocalItem('eg.cat.marked_overlay_record')) {
                this.store.removeLocalItem('eg.cat.marked_overlay_record');
                console.debug('...target removed');
            }
            if (this.currentEditFastItem) {
                const fastItem = this.currentEditFastItem;
                this.currentEditFastItem = null;
                this.holdings.spawnAddHoldingsUi(previous_target, null, [fastItem]);
            } else {
                window.open('/eg2/staff/catalog/record/' + previous_target, '_blank');
            }
        });
    }

    // store selected targets
    saveDefaultZ3950Targets(alrt?:boolean) {
        this.zService.saveDefaultZ3950Targets();
        if (alrt === true) {this.toast.success($localize`Selected targets saved`);}
    }

    // store default field
    saveDefaultField(e) {
        this.zService.saveDefaultField(this.defaultField);
        // this.toast.success($localize`Default field saved: ${this.fieldLabelByName(this.defaultField)}`)
    }

    performSearch() {
        this.saveDefaultZ3950Targets(false);
        this.resultGrid.reload();
    }

    showRawSearch() {
        this.rawSearchPrompt.open({size: 'lg'}).subscribe(
            c => { this.rawSearch = c.trim(); if (this.rawSearch) {this._fromRaw = true;} },
            (e: unknown) => {},
            () => { if (this._fromRaw) {this.performSearch();} }
        );
    }

    selectedRows() {
        return this
            .resultGrid
            .context
            .rowSelector
            .selected()
            .map(id => this.resultGrid.context.getRowByIndex(id));
    }

    selectedLocalRows() {
        return this
            .selectedRows()
            .filter(r => r && r.service === 'native-evergreen-catalog');
    }

    noneSelected() {
        return !!(this.selectedRows().length == 0);
    }

    noneSelectedForGrid(rows: any) {
        return !!(rows.length == 0);
    }

    oneSelected() {
        return !!(this.selectedRows().length == 1);
    }

    notOneSelectedForGrid(rows: any) {
        return !(rows.length === 1);
    }

    cant_overlayForGrid(rows: any) {
        if (rows.length != 1) {return true;}
        if (rows[0]['service'] == 'native-evergreen-catalog') {return true;}
        return false;
    }



    oneLocalSelected() {
        if (this.selectedRows().length == 1) {
            if (this.selectedLocalRows().length == 1) {
                return true;
            }
        }
        return false;
    }

    notOneLocalSelectedForGrid(rows: any) {
        if (rows.length === 1 && rows[0].service === 'native-evergreen-catalog') {
            return false;
        }

        return true;
    }

    markOverlayTarget(rows: any) {
        if (rows.length === 1 && rows[0].service === 'native-evergreen-catalog') {
            if (!!this.overlayTarget && this.overlayTarget == rows[0]['bibid']) { // same one, UN-set!
                this.overlayTarget = null;
            } else {
                const recheck_target = this.store.getLocalItem('eg.cat.marked_overlay_record');
                if (!(this.overlayTarget != recheck_target)) { // changed elsewhere, don't save it!
                    this.store.setLocalItem('eg.cat.marked_overlay_record', this.overlayTarget);
                }
                this.overlayTarget = rows[0]['bibid'];
                this.get_tcn(this.overlayTarget).then( t => this.overlayTargetTCN = t );
            }
        }
    }

    showInCatalog( rows: any ) {
        window.open('/eg2/staff/catalog/record/'+rows[0]['bibid'], '_blank');
    }

    permittedTargets() {
        if (!this.includeNativeCatalog) {
            return this.zService.targets.filter(t => t.code !== 'native-evergreen-catalog');
        }

        return this.zService.targets;
    }

    localTargetIsSelected() {
        return !!(this.zService.selectedTargets().find(t => t.code === 'native-evergreen-catalog'));
    }

    oneTargetIsSelected() {
        return this.zService.selectedTargets().length === 1;
    }

    selectedTargets() {
        if (!this.includeNativeCatalog) {
            return this.zService.selectedTargets().filter(t => t.code !== 'native-evergreen-catalog');
        }

        return this.zService.selectedTargets();
    }

    currentQuery() {
        const query = {
            service   : [],
            username  : [],
            password  : [],
            search    : {},
            raw_search: ''
        };

        this.zService.selectedTargets().forEach(t => {
            query.service.push(t.code);
            query.username.push(t.username);
            query.password.push(t.password);
        });

        query['raw_search'] = this.rawSearch;

        this.currentFields.forEach(f => {
            if (f.searchTerms && f.searchTerms.trim()) {
                query.search[f.name] = f.searchTerms.trim();
            }
        });


        return query;
    }

    sourceSelectionChange(src) {
        src.selected = !src.selected;
        const prevFields = this.currentFields.map(f => { return {name: f.name, field: f};}); // replacing this, grab it for the searchTerms
        this.currentFields = this.fieldsGroupedByNameForSelectedTargets();
        this.currentFields.forEach(f => {
            const old = prevFields.find(p => p.name === f.name);
            if (old) {f.searchTerms = old.field.searchTerms;}
        });

    }

    fieldsGroupedByNameForSelectedTargets() {
        // gather fields (attrs) for selected sources
        // (a subset of permittedTargets()) and group
        // them by "name" (pkey).
        const groupedFields = {};
        this.zService.selectedTargets().forEach(t => {
            Object.entries(t.settings.attrs).forEach(([k,v]) => {
                if (!groupedFields[k]) {
                    groupedFields[k] = {
                        name:    k,
                        labels:  [v['label']],
                        sources: [t],
                        source_labels: [t.settings.label],
                        searchTerms: ''
                    };
                } else {
                    groupedFields[k]['labels'].push(v['label']);
                    groupedFields[k]['sources'].push(t);
                    groupedFields[k]['source_labels'].push(t.settings.label);
                }
            });
        });

        return Object.values(groupedFields).sort((a,b) => {
            a = a['labels'][0].toLowerCase();
            b = b['labels'][0].toLowerCase();
            return a < b ? -1 : (a > b ? 1 : 0);
        });
    }
}

@Directive({
    selector: '[egautofocus]'
})
export class AutofocusDirective implements OnInit {
    @Input() egautofocus: boolean;

    constructor(private host: ElementRef) {}

    ngOnInit() {
        if (this.egautofocus) {this.host.nativeElement.focus();}
    }
}
