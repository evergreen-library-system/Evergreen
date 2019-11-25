import {Component, Input, ViewChild, OnInit, TemplateRef} from '@angular/core';
import {Observable, Observer, of} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';

@Component({
    selector: 'eg-course-associate-material-dialog',
    templateUrl: './course-associate-material.component.html'
})

export class CourseAssociateMaterialComponent extends DialogComponent {

    @ViewChild('materialsGrid', {static: true}) materialsGrid: GridComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('failedString', { static: true }) failedString: StringComponent;
    @ViewChild('differentLibraryString', { static: true }) differentLibraryString: StringComponent;
    @Input() table_name = "Course Materials";
    @Input() barcodeInput: String;
    @Input() relationshipInput: String;
    @Input() tempCallNumber: String;
    @Input() tempStatus: Number;
    @Input() tempLocation: Number;
    @Input() tempCircMod: String;
    @Input() isModifyingStatus: Boolean;
    @Input() isModifyingCircMod: Boolean;
    @Input() isModifyingCallNumber: Boolean;
    @Input() isModifyingLocation: Boolean;
    currentCourse: IdlObject;
    materials: any[];
    gridDataSource: GridDataSource;

    constructor(
        private auth: AuthService,
        private idl: IdlService,
        private net: NetService,
        private pcrud: PcrudService,
        private org: OrgService,
        private evt: EventService,
        private modal: NgbModal,
        private toast: ToastService,
        private courseSvc: CourseService
    ) {
        super(modal);
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.fetchMaterials(pager);
        }
    }

    deleteSelected(items) {
        let item_ids = [];
        items.forEach(item => {
            this.gridDataSource.data.splice(this.gridDataSource.data.indexOf(item, 0), 1);
            item_ids.push(item.id())
        });
        this.pcrud.search('acmcm', {course: this.currentCourse.id(), item: item_ids}).subscribe(material => {
            material.isdeleted(true);
            this.pcrud.autoApply(material).subscribe(
                val => {
                    this.courseSvc.resetItemFields(material, this.currentCourse.owning_lib());
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current().then(str => this.toast.success(str));
                },
                err => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }
            );
        });
    }

    associateItem(barcode, relationship) {
        if (barcode) {
            this.pcrud.search('acp', {barcode: barcode},
              {flesh: 3, flesh_fields: {acp: ['call_number']}}).subscribe(item => {
                let material = this.idl.create('acmcm');
                material.item(item.id());
                material.course(this.currentCourse.id());
                if (relationship) material.relationship(relationship);
                if (this.isModifyingStatus && this.tempStatus) {
                    material.original_status(item.status());
                    item.status(this.tempStatus);
                }
                if (this.isModifyingLocation && this.tempLocation) {
                    material.original_location(item.location());
                    item.location(this.tempLocation);
                }
                if (this.isModifyingCircMod) {
                    material.original_circ_modifier(item.circ_modifier());
                    item.circ_modifier(this.tempCircMod);
                    if (!this.tempCircMod) item.circ_modifier(null);
                }
                if (this.isModifyingCallNumber) {
                    material.original_callnumber(item.call_number());
                }
                this.pcrud.create(material).subscribe(
                val => {
                   console.debug('created: ' + val);
                   let new_cn = item.call_number().label();
                   if (this.tempCallNumber) new_cn = this.tempCallNumber;
                    this.courseSvc.updateItem(item, this.currentCourse.owning_lib(), new_cn, this.isModifyingCallNumber).then(res => {
                        this.fetchItem(item.id(), relationship);                        
                        if (item.circ_lib() != this.currentCourse.owning_lib()) {
                            this.differentLibraryString.current().then(str => this.toast.warning(str));
                        } else {
                            this.successString.current().then(str => this.toast.success(str));
                        }
                    });

                    // Cleaning up inputs
                    this.barcodeInput = "";
                    this.relationshipInput = "";
                    this.tempStatus = null;
                    this.tempCircMod = null;
                    this.tempCallNumber = null;
                    this.tempLocation = null;
                    this.isModifyingCallNumber = false;
                    this.isModifyingCircMod = false;
                    this.isModifyingLocation = false;
                    this.isModifyingStatus = false;
                }, err => {
                    this.failedString.current().then(str => this.toast.danger(str));
                });
            });
        }
    }

    fetchMaterials(pager: Pager): Observable<any> {
        return new Observable<any>(observer => {
            this.materials.forEach(material => {
                this.fetchItem(material.item, material.relationship);
            });
            observer.complete();
        });
    }

    fetchItem(itemId, relationship): Promise<any> {
        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.copy_details.retrieve',
                this.auth.token(), itemId
            ).subscribe(res => {
                if (res) {
                    let item = res.copy;
                    item.call_number(res.volume);
                    item.circ_lib(this.org.get(item.circ_lib()));
                    item._title = res.mvr.title();
                    item._relationship = relationship;
                    this.gridDataSource.data.push(item);
                }
            }, err => {
                reject(err);
            }, () => resolve(this.gridDataSource.data));
        });
    }
}