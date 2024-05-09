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
    templateUrl: './sr-editor.component.html',
    styleUrls: ['./sr-editor.component.css'],
})

export class SREditorComponent implements OnInit {

    rptType = '';
    oldRptType = '';
    name = '';
    templ: SRTemplate = null;
    isNew = true;
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
        private srSvc: ReporterService
    ) {
        const id = this.route.snapshot.paramMap.get('id');
        if ( id === null ) {
            this.templ = new SRTemplate();
        } else {
            this.isNew = false;
            this.loadTemplate(Number(id))
                .then( x => this.reloadFields(this.templ.fmClass));
        }

    }

    ngOnInit() {
        this._setPageTitle();
    }

    _setPageTitle() {
        if ( this.isNew ) {
            this.newTitleString.current()
                .then(str => this.pageTitle = str );
        } else {
            this.editTitleString.current()
                .then(str => this.pageTitle = str );
        }
    }

    reloadFields(fmClass: string) {
        this.allFields = [];
        this.forcedFields = 0;
        this.sourceClass = this.idl.classes[fmClass];
        // eslint-disable-next-line no-unused-expressions
        ('field_groups' in this.sourceClass) ?
            // grab a clone
            this.fieldGroups = this.sourceClass.field_groups.map(x => ({...x})) :
            this.fieldGroups = [];

        this.sourceClass.fields.forEach(f => {

            f.transform = this.srSvc.defaultTransform();
            f.operator = this.srSvc.defaultOperator(f.datatype);

            if ( f.suggest_transform ) {
                f.transform = this.srSvc.getTransformByName(f.suggest_transform);
            }

            if ( f.suggest_operator ) {
                f.operator = this.srSvc.getOperatorByName(f.suggest_operator);
            }

            if ( f.force_transform ) {
                if ( typeof f.force_transform === 'string' ) {
                    f.transform = this.srSvc.getTransformByName(f.force_transform);
                } else {
                    f.transform = this.srSvc.getGenericTransformWithParams(f.force_transform);
                }
            }

            if ( f.force_operator ) {
                f.operator = this.srSvc.getOperatorByName(f.force_operator);
            }

            if ( f.force_filter ) {
                if ( this.templ.filterFields.findIndex(el => el.name === f.name) === -1 ) {
                    this.templ.filterFields.push(f);
                    this.forcedFields++;
                }
            }

            this.allFields.push(f);
            if ( 'field_groups' in f ) {
                f.field_groups.forEach(g => {
                    const idx = this.fieldGroups.findIndex(el => el.name === g);
                    if ( idx > -1 ) {
                        if ( !('members' in this.fieldGroups[idx]) ) {
                            this.fieldGroups[idx].members = [];
                        }
                        this.fieldGroups[idx].members.push(f);
                    }
                });
            }
        });

        this.allFields.sort( (a, b) => a.label.localeCompare(b.label) );

    }

    changeReportType() {
        if ( this.oldRptType === '' || (this.templ.displayFields.length === 0 && this.templ.filterFields.length === this.forcedFields) ) {
            this.oldRptType = this.rptType;
            this.templ = new SRTemplate();
            this.templ.fmClass = this.rptType;
            this.reloadFields(this.rptType);
            this._isDirty = true;
        } else {
            return this.changeTypeDialog.open()
                .subscribe(confirmed => {
                    if ( confirmed ) {
                        this.oldRptType = this.rptType;
                        this.templ = new SRTemplate();
                        this.templ.fmClass = this.rptType;
                        this.reloadFields(this.rptType);
                        this._isDirty = true;
                    } else {
                        this.rptType = this.oldRptType;
                    }
                });
        }
    }

    dirty() {
        this._isDirty = true;
    }

    isDirty() {
        return this._isDirty;
    }

    readyToSave() {
        return ( this.sourceClass !== null && this.name !== '' );
    }

    readyToSchedule = () => {
        return ( this.readyToSave() && this.templ.displayFields.length > 0 );
    };

    canLeaveEditor() {
        if ( this.isDirty() ) {
            return this.closeFormDialog.open();
        } else {
            return of(true);
        }
    }

    loadTemplate(id: number) {
        return this.srSvc.loadTemplate(id)
            .then(idl => {
                this.templ = new SRTemplate(idl);
                this.name = this.templ.name;
                this.rptType = this.templ.fmClass;
                this.oldRptType = this.templ.fmClass;
            });
    }

    saveTemplate = (scheduleNow) => {
        this.templ.name = this.name;

        this.srSvc.saveSimpleTemplate(this.templ, scheduleNow)
            .then(rt => {
                this._isDirty = false;
                // It appears that calling pcrud.create will return the newly created object,
                // while pcrud.update just gives you back the id of the updated object.
                if ( typeof rt === 'object' ) {
                    this.templ = new SRTemplate(rt); // pick up the id and create_time fields
                }
                this.templateSavedString.current()
                    .then(str => {
                        this.toast.success(str);
                    });
                if (scheduleNow) {
                // we're done, so jump to the main page
                    this.router.navigate(['/staff/reporter/simple']);
                } else if (this.isNew) {
                // we've successfully saved, so we're no longer new
                // adjust page title...
                    this.isNew = false;
                    this._setPageTitle();
                    // ... and make the URL say that we're editing
                    const url = this.router.createUrlTree(['/staff/reporter/simple/edit/' + this.templ.id]).toString();
                    this.location.go(url); // go without reloading
                }
            },
            err => {
                this.templateSaveErrorString.current()
                    .then(str => {
                        this.toast.danger(str + err);
                        console.error('Error saving template: %o', err);
                    });
            });
    };

    closeForm() {
        this.router.navigate(['/staff/reporter/simple']);
    }

}

