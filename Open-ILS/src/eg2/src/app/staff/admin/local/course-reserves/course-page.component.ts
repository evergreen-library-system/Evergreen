import {Component, Input, ViewChild, OnInit, TemplateRef} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
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
import {StaffBannerComponent} from '@eg/staff/share/staff-banner.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';

@Component({
    selector: 'eg-course-page',
    templateUrl: './course-page.component.html'
})

export class CoursePageComponent implements OnInit {

    currentCourse: IdlObject;
    courseId: any;
    
    // Edit Tab
    @ViewChild('archiveFailedString', { static: true })
        archiveFailedString: StringComponent;
    @ViewChild('archiveSuccessString', { static: true })
        archiveSuccessString: StringComponent;

    // Materials Tab
    materials: any[] = [];
    @ViewChild('materialsGrid', {static: true}) materialsGrid: GridComponent;
    @ViewChild('materialDeleteFailedString', { static: true })
        materialDeleteFailedString: StringComponent;
    @ViewChild('materialDeleteSuccessString', { static: true })
        materialDeleteSuccessString: StringComponent;
    @ViewChild('materialAddSuccessString', { static: true })
        materialAddSuccessString: StringComponent;
    @ViewChild('materialAddFailedString', { static: true })
        materialAddFailedString: StringComponent;
    @ViewChild('materialAddDifferentLibraryString', { static: true })
        materialAddDifferentLibraryString: StringComponent;
    materialsDataSource: GridDataSource;
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

    // Users Tab
    @Input() userBarcode: String;
    @Input() userRoleInput: String;
    constructor(
        private auth: AuthService,
        private course: CourseService,
        private event: EventService,
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
        private toast: ToastService
    ) {
        this.materialsDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.courseId = parseInt(this.route.snapshot.paramMap.get('id'));
        this.course.getCourses([this.courseId]).then(course => {
            this.currentCourse = course[0];
        });
        this.materialsDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.loadMaterialsGrid(pager);
        }
    }

    // Edit Tab
    archiveCourse() {
        this.course.disassociateMaterials([this.currentCourse]).then(res => {
            this.currentCourse.is_archived('t');
            this.pcrud.update(this.currentCourse).subscribe(val => {
                console.debug('archived: ' + val);
                this.archiveSuccessString.current()
                    .then(str => this.toast.success(str));
            }, err => {
                this.archiveFailedString.current()
                    .then(str => this.toast.danger(str));
            });
        });
    }

    // Materials Tab
    loadMaterialsGrid(pager: Pager): Observable<any> {
        return new Observable<any>(observer => {
            this.course.getMaterials(this.courseId).then(materials => {
                materials.forEach(material => {
                    this.course.fleshMaterial(material.item(), material.relationship()).then(fleshed_material => {
                        this.materialsDataSource.data.push(fleshed_material);
                    });
                });
            });
            observer.complete();
        });
    }
    
    associateItem(barcode, relationship) {
        if (barcode) {
            let args = {
                barcode: barcode,
                relationship: relationship,
                isModifyingCallNumber: this.isModifyingCallNumber,
                isModifyingCircMod: this.isModifyingCircMod,
                isModifyingLocation: this.isModifyingLocation,
                isModifyingStatus: this.isModifyingStatus,
                tempCircMod: this.tempCircMod,
                tempLocation: this.tempLocation,
                tempStatus: this.tempStatus,
                currentCourse: this.currentCourse
            }
            this.barcodeInput = null;

            this.pcrud.search('acp', {barcode: args.barcode}, {
                flesh: 3, flesh_fields: {acp: ['call_number']}
            }).subscribe(item => {
                let associatedMaterial = this.course.associateMaterials(item, args);
                associatedMaterial.material.then(res => {
                    item = associatedMaterial.item;
                    let new_cn = item.call_number().label();
                    if (this.tempCallNumber) new_cn = this.tempCallNumber;
                    this.course.updateItem(item, this.currentCourse.owning_lib(),
                        new_cn, args.isModifyingCallNumber
                    ).then(resp => {
                        this.course.fleshMaterial(item.id(), args.relationship).then(fleshed_material => {
                            this.materialsDataSource.data.push(fleshed_material);
                        });
                        if (item.circ_lib() != this.currentCourse.owning_lib()) {
                            this.materialAddDifferentLibraryString.current()
                            .then(str => this.toast.warning(str));
                        } else {
                            this.materialAddSuccessString.current()
                            .then(str => this.toast.success(str));
                        }
                    });
                }, err => {
                    this.materialAddFailedString.current()
                    .then(str => this.toast.danger(str));
                });
            });
        }
    }

    deleteSelected(items) {
        let item_ids = [];
        items.forEach(item => {
            this.materialsDataSource.data.splice(this.materialsDataSource.data.indexOf(item, 0), 1);
            item_ids.push(item.id())
        });
        this.pcrud.search('acmcm', {course: this.courseId, item: item_ids}).subscribe(material => {
            material.isdeleted(true);
            this.pcrud.autoApply(material).subscribe(
                val => {
                    this.course.resetItemFields(material, this.currentCourse.owning_lib());
                    console.debug('deleted: ' + val);
                    this.materialDeleteSuccessString.current().then(str => this.toast.success(str));
                },
                err => {
                    this.materialDeleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }
            );
        });
    }
}