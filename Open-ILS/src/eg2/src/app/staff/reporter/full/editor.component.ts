/* eslint-disable */
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
import {Tree, TreeNode} from '@eg/share/tree/tree';

@Component({
    templateUrl: './editor.component.html',
    styleUrls: ['./editor.component.css'],
})

export class FullReporterEditorComponent implements OnInit {

    currentIdlTree: Tree = null;
    currentIdlNode: TreeNode = null;
    rptType = '';
    oldRptType = '';
    name = '';
    doc_url = '';
    description = '';
    templ: SRTemplate = null;
    isNew = true;
    isClone = false;
    isEdit = false;
    sourceClass: IdlObject = null;
    fieldGroups: IdlObject[] = [];
    allFields: IdlObject[] = [];
    pageTitle = '';
    forcedFields = 0;
    folder: IdlObject = null;
    folderTree: Tree = null;
    _isDirty = false;
    folderParam: number;

    @ViewChild('templateSaved', { static: true }) templateSavedString: StringComponent;
    @ViewChild('templateSaveError', { static: true }) templateSaveErrorString: StringComponent;
    @ViewChild('newTitle', { static: true }) newTitleString: StringComponent;
    @ViewChild('editTitle', { static: true }) editTitleString: StringComponent;
    @ViewChild('cloneTitle', { static: true }) cloneTitleString: StringComponent;
    @ViewChild('EditorTabs', { static: true }) tabs: NgbNav;
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
        public RSvc: ReporterService
    ) {
        this.folderParam = Number(this.route.snapshot.paramMap.get('folder')) || null;
        if (this.folderParam) {
            this.pcrud
                .retrieve('rtf', this.folderParam)
                .subscribe(fldr => this.folder = this.RSvc.templateFolder = fldr);
        }

        const id = this.route.snapshot.paramMap.get('id');
        if ( id === null ) {
            this.templ = new SRTemplate();
        } else {
            this.isClone = this.route.snapshot.url.map(s => s.toString()).filter(s => s === 'clone').length > 0;
            this.isEdit = this.route.snapshot.url.map(s => s.toString()).filter(s => s === 'edit').length > 0;
            this.isNew = false;
            this.loadTemplate(Number(id))
                .then( x => this.name += (this.isClone ? ' (Clone)' : ''))
                .then( x => this.templ.create_time = this.isClone ? 'now' : this.templ.create_time)
                .then( x => this.reloadFields(this.templ.fmClass));
        }

    }

    ngOnInit() {
        this._setPageTitle();
        if (!this.RSvc.myFolderTrees.templates.rootNode.children.length) { // hard refresh? bookmark?
            this.RSvc.reloadFolders().then(() => {
                this.folderTree = this.RSvc.myFolderTrees.templates.clone({expanded:!this.folderParam});
            });
        } else {
            this.folderTree = this.RSvc.myFolderTrees.templates.clone({expanded:!this.folderParam});
        }
    }

    _setPageTitle() {
        if ( this.isNew ) {
            this.newTitleString.current()
                .then(str => this.pageTitle = str );
        } else if (this.isClone) {
            this.cloneTitleString.current()
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
        ('field_groups' in this.sourceClass) ?
            // grab a clone
            this.fieldGroups = this.sourceClass.field_groups.map(x => ({...x})) :
            this.fieldGroups = [];

        this.sourceClass.fields.forEach(f => {

            f.path = this.currentIdlTree.findNodePath(this.currentIdlNode);
            f.treeNodeId = this.currentIdlNode.id + '.' + f.name;
            f.transform = this.RSvc.defaultTransform();
            f.operator = this.RSvc.defaultOperator(f.datatype);

            if ( f.suggest_transform ) {
                f.transform = this.RSvc.getTransformByName(f.suggest_transform);
            }

            if ( f.suggest_operator ) {
                f.operator = this.RSvc.getOperatorByName(f.suggest_operator);
            }

            if ( f.force_transform ) {
                if ( typeof f.force_transform === 'string' ) {
                    f.transform = this.RSvc.getTransformByName(f.force_transform);
                } else {
                    f.transform = this.RSvc.getGenericTransformWithParams(f.force_transform);
                }
            }

            if ( f.force_operator ) {
                f.operator = this.RSvc.getOperatorByName(f.force_operator);
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
            this._isDirty = true;
            this.currentIdlTree = null;
    		this.treeFromRptType();
            this.reloadFields(this.rptType);
        } else {
            return this.changeTypeDialog.open()
                .subscribe(confirmed => {
                    if ( confirmed ) {
                        this.oldRptType = this.rptType;
                        this.templ = new SRTemplate();
                        this.templ.fmClass = this.rptType;
                        this._isDirty = true;
                        this.currentIdlTree = null;
    				this.treeFromRptType();
                        this.reloadFields(this.rptType);
                    } else {
                        this.rptType = this.oldRptType;
                    }
                });
        }
    }

    idlTreeNodeSelected (node: TreeNode) {
        this.currentIdlNode = node;
        this.reloadFields(node.callerData.fmClass);
        console.log('Tree node selected:', node);
    }

    folderNodeSelected (node: TreeNode) {
        if (node && node.callerData && node.callerData.folderIdl) {
            this.folder = node.callerData.folderIdl;
            this.folderTree.collapseAll();
            this.RSvc.templateFolder = this.folder;
            let newPath = this.location.path();
            if (!this.folderParam) {
                this.folderParam = this.folder.id();
                newPath = newPath + '/' + this.folderParam as string;
            } else {
                this.folderParam = this.folder.id();
                newPath = newPath.replace(/\d+$/, (this.folderParam as unknown) as string);
            }
            this.location.go(newPath);
            console.log('folder node selected:', node);
        }
    }

    idlTreeNodeRequired (node: TreeNode) {
        this.reloadFields(this.currentIdlNode.callerData.fmClass);
        console.log('Tree node required flag:', node);
    }

    treeFromRptType() {
        if (!this.rptType || this.currentIdlTree) {return;}

        const get_kids  = (node: TreeNode) => {
            const idl_class = this.idl.classes[node.callerData.fmClass];
            const parent_id = node.id;

            const kids = [];
            const linked = [];
            const nonlinked = [];
            idl_class.fields.sort( (a,b) => a.label.localeCompare(b.label) ).forEach(f => {
                if (f.class) {
                    kids.push(
                        new TreeNode({
                            id: parent_id + '.' + f.name + ':' + f.key + '@' + f.class,
                            stateFlag: false,
                            stateFlagLabel: $localize`Require INNER join between ${node.label} and ${f.label}?`,
        					label: f.label || f.name,
                            expanded: false,
                            childrenCB: get_kids,
				            callerData: {
                                parent_id: parent_id,
			    	    		fmClass: f.class,
			    	    		fmField: {
                                    key: f.key,
                                    name: ['has_many','might_have'].includes(f.reltype) ? idl_class.pkey : f.name,
                                    reltype: f.reltype,
                                    class: f.class // field on parent; (stateFlag ? '' : LEFT) JOIN fmclass.tablename ON (fmField.name [lhs] = fmField.key [rhs])
                                }
                            }
                        })
                    );
                }
            });

            return kids;
        };

        const core_class = this.idl.classes[this.rptType];

        const node: TreeNode = new TreeNode({
            id: core_class.name,
            label: core_class.label || core_class.name,
            selected: true,
            childrenCB: get_kids,
            callerData: {
                fmClass: core_class.name
            }
        });

        this.currentIdlTree = new Tree(node);
        this.currentIdlNode = node;
        this.currentIdlTree.nodeList(true);
    }

    dirty() {
        this._isDirty = true;
    }

    isDirty() {
        return this._isDirty;
    }

    readyToSave() {
        return ( this.folder && this.sourceClass !== null && this.name !== '' );
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
        return this.RSvc.loadTemplate(id)
            .then(idl => {
                this.templ = new SRTemplate(idl, true); // Second param says "template only", don't look at previous report definitions
                this.templ.isNew = this.isNew || this.isClone; // this forces a new ID
                this.name = this.templ.name;
                this.doc_url = this.templ.doc_url;
                this.description = this.templ.description;
                this.rptType = this.templ.fmClass;
                this.oldRptType = this.templ.fmClass;
    		this.treeFromRptType();
            });
    }

    saveTemplate = (scheduleNow) => {
        this.templ.name = this.name;
        this.templ.doc_url = this.doc_url;
        this.templ.description = this.description;

        this.RSvc.saveTemplate(this.templ)
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
                    this.RSvc.currentFolderType = null;
                    this.router.navigate(['/staff/reporter/full']);
                } else if (this.isNew || this.isClone) {
                // we've successfully saved, so we're no longer new
                // adjust page title...
                    this.isNew = false;
                    this._setPageTitle();
                    // ... and make the URL say that we're editing
                    let folder_path = '';
                    if (this.folder) {
                        folder_path = '/' + this.folder.id();
                    }
                    const url = this.router.createUrlTree(['/staff/reporter/full/edit/' + this.templ.id + folder_path]).toString();
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
        this.RSvc.currentFolderType = null;
        this.router.navigate(['/staff/reporter/full']);
    }

}

