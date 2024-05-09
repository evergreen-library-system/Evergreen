import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Location} from '@angular/common';
import {of} from 'rxjs';
import {NgbNav} from '@ng-bootstrap/ng-bootstrap';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ReporterService, SRTemplate} from '../share/reporter.service';

@Component({
    templateUrl: './definition.component.html',
    styleUrls: ['./definition.component.css'],
})

export class FullReporterDefinitionComponent implements OnInit {

    selectedTab = 'rptFilterFields';
    rptType = '';
    oldRptType = '';
    name = '';
    description = '';
    templ: SRTemplate = null;
    rpt: IdlObject = null;
    isNew = true;
    isClone = false;
    isEdit = false;
    isView = false;
    reportIdl: IdlObject = null;
    sourceClass: IdlObject = null;
    fieldGroups: IdlObject[] = [];
    allFields: IdlObject[] = [];
    pageTitle = '';
    forcedFields = 0;
    _isDirty = false;

    @ViewChild('templateSaved', { static: true }) templateSavedString: StringComponent;
    @ViewChild('templateSaveError', { static: true }) templateSaveErrorString: StringComponent;
    @ViewChild('newTitle', { static: true }) newTitleString: StringComponent;
    @ViewChild('editTitle', { static: true }) editTitleString: StringComponent;
    @ViewChild('viewTitle', { static: true }) viewTitleString: StringComponent;
    @ViewChild('cloneTitle', { static: true }) cloneTitleString: StringComponent;
    @ViewChild('srEditorTabs', { static: true }) tabs: NgbNav;
    @ViewChild('changeTypeDialog', { static: false }) changeTypeDialog: ConfirmDialogComponent;
    @ViewChild('closeFormDialog', { static: false }) closeFormDialog: ConfirmDialogComponent;

    constructor(
        private route: ActivatedRoute,
        private router: Router,
        private location: Location,
        private toast: ToastService,
        private evt: EventService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private RSvc: ReporterService
    ) {
        const t_id = this.route.snapshot.paramMap.get('t_id');
        const r_id = this.route.snapshot.paramMap.get('r_id');
        this.RSvc.outputFolder = null;
        if (t_id) {
            // new report from template
            this.RSvc.reportFolder = null;
            this.isNew = true;
            this.loadTemplate(Number(t_id))
                .then( x => this._setPageTitle());
        } else if (r_id) {
            // editing a report definition (maybe a clone?)
            this.isClone = this.route.snapshot.url.map(s => s.toString()).filter(s => s === 'clone').length > 0;
            this.isEdit = this.route.snapshot.url.map(s => s.toString()).filter(s => s === 'edit').length > 0;
            this.isView = this.route.snapshot.url.map(s => s.toString()).filter(s => s === 'view').length > 0;
            this.isNew = false;
            this.loadReport(Number(r_id))
                .then( x => this.name += (this.isClone ? ' (Clone)' : ''))
                .then( x => this._setPageTitle());
        }
    }

    changeToTab = tab => this.selectedTab = tab;

    ngOnInit() {
        this._setPageTitle();
    }

    _setPageTitle() {
        if ( this.isNew ) {
            this.newTitleString.current()
                .then(str => this.pageTitle = str );
        } else if (this.isClone) {
            this.cloneTitleString.current()
                .then(str => this.pageTitle = str );
        } else if (this.isView) {
            this.viewTitleString.current()
                .then(str => this.pageTitle = str );
        } else {
            this.editTitleString.current()
                .then(str => this.pageTitle = str );
        }
    }

    dirty() {
        this._isDirty = true;
    }

    isDirty() {
        return this._isDirty;
    }

    setOrHasLength (x: any) {
        if (x === null) {
            return false;
        } else if (Array.isArray(x)) {
            return x.length > 0;
        } else if (typeof x === 'object') {
            return Object.keys(x).length > 0;
        }
        return !!x;
    }

    filtersWithoutValues () {
        return this.templ.filterFields.filter( f => {
            if (f.with_value_input) {return false;}
            if (f.operator.arity == 0) {return false;} // is [not] null
            if (f.datatype == 'text'
                && f.operator.arity == 1
                && f.hasOwnProperty('filter_value')
                && f.filter_value !== null
            ) {return false;} // text comparator, value not null
            return !this.setOrHasLength(f.filter_value);
        });
    }

    readyToSave() {
        return (
            this.name !== ''
            && this.RSvc.reportFolder
            && this.filtersWithoutValues().length == 0
        );
    }

    readyToSchedule = () => {
        return ( this.readyToSave() && this.templ.displayFields.length > 0 && this.RSvc.outputFolder);
    };

    hideField(field: IdlObject) {
        if ( typeof field.hide_from === 'undefined' ) {
            return false;
        }
        return (field.hide_from.indexOf('filter') > -1);
    }

    canLeaveEditor() {
        if ( this.isDirty() ) {
            return this.closeFormDialog.open();
        } else {
            return of(true);
        }
    }

    loadTemplate(id: number) {
        return this.RSvc.loadTemplate(id)
            .then(idl => {
                this.templ = new SRTemplate(idl, true);
                this.name = this.templ.name;
                this.rptType = this.templ.fmClass;
                this.oldRptType = this.templ.fmClass;
            });
    }

    loadReport(id: number) {
        return this.RSvc.loadReport(id)
            .then(idl => {
                const t = idl.template();
                idl.template(t.id());
                t.reports([idl]);

                this.RSvc.reportFolder = this.RSvc
                    .myFolderTrees
                    .reports
                    .findNode(idl.folder())
                    .callerData
                    .folderIdl;

                this.reportIdl = idl;
                this.templ = new SRTemplate(t);
                this.templ.rrIdl = idl;
                this.name = idl.name();
                this.description = idl.description();

                this.rptType = this.templ.fmClass;
                this.oldRptType = this.templ.fmClass;
            });
    }

    saveAndScheduleDefinition(leaveNow = true) {
        this.saveDefinition(leaveNow, true);
    }

    saveDefinition(leaveNow = true, scheduleNow = false) {

        this.RSvc.saveReportDefinition(this.templ, this.name, this.description, this.isEdit, scheduleNow)
            .then(
                rr => {
                    this._isDirty = false;
                    this.templateSavedString.current()
                        .then(str => {
                            this.toast.success(str);
                        });
                    if (leaveNow) {
                        this.RSvc.currentFolderType = null;
                        this.router.navigate(['/staff/reporter/full']);
                    }
                },
                err => {
                    this.templateSaveErrorString.current()
                        .then(str => {
                            this.toast.danger(str + err);
                            console.error('Error saving report definition: %o', err);
                        });
                }
            );
    }

    closeForm() {
        this.RSvc.currentFolderType = null;
        this.router.navigate(['/staff/reporter/full']);
    }

}

