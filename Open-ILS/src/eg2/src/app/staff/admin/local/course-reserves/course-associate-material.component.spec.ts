import { PermService } from '@eg/core/perm.service';
import { ComponentFixture, TestBed, waitForAsync } from '@angular/core/testing';
import { ToastService } from '@eg/share/toast/toast.service';
import { CourseService } from '@eg/staff/share/course.service';
import { AuthService } from '@eg/core/auth.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { CourseAssociateMaterialComponent } from './course-associate-material.component';
import {NgbModal, NgbNav} from '@ng-bootstrap/ng-bootstrap';
import { of } from 'rxjs';
import { DialogComponent } from '@eg/share/dialog/dialog.component';
import { NO_ERRORS_SCHEMA } from '@angular/core';


describe('CourseAssociateMaterialComponent', () => {
    let component: CourseAssociateMaterialComponent;
    let fixture: ComponentFixture<CourseAssociateMaterialComponent>;

    const mockLibrary = {
        id: () => 5,
        shortname: () => 'greatLibrary'
    };

    const mockLibrary2 = {
        id: () => 22
    };

    const mockItem = {
        a: [],
        classname: 'acp',
        _isfieldmapper: true,
        id: () => {},
        circ_lib: () => mockLibrary
    };

    const mockCourse = {
        a: [],
        classname: 'acmc',
        _isfieldmapper: true,
        owning_lib: () => mockLibrary2,
        course_number: () => 'HIST123'
    };

    const courseServiceSpy = jasmine.createSpyObj<CourseService>(['associateMaterials']);
    courseServiceSpy.associateMaterials.and.returnValue({item: mockItem, material: new Promise(() => {})});
    const netServiceSpy = jasmine.createSpyObj<NetService>(['request']);
    const pcrudServiceSpy = jasmine.createSpyObj<PcrudService>(['retrieveAll', 'search', 'update']);
    pcrudServiceSpy.search.and.returnValue(of(mockItem));
    const toastServiceSpy = jasmine.createSpyObj<ToastService>(['success']);
    const permServiceSpy = jasmine.createSpyObj<PermService>(['hasWorkPermAt']);
    permServiceSpy.hasWorkPermAt.and.returnValue(new Promise((resolve) => resolve({UPDATE_COPY: [5, 22]})));
    const modalSpy = jasmine.createSpyObj<NgbModal>(['open']);
    const dialogComponentSpy = jasmine.createSpyObj<DialogComponent>(['open']);
    dialogComponentSpy.open.and.returnValue(of(true));
    const rejectedDialogComponentSpy = jasmine.createSpyObj<DialogComponent>(['open']);
    rejectedDialogComponentSpy.open.and.returnValue(of(false));

    beforeEach(waitForAsync(() => {
        TestBed.configureTestingModule({
            providers: [
                {provide: AuthService, useValue: jasmine.createSpyObj<AuthService>(['token'])},
                {provide: CourseService, useValue: courseServiceSpy},
                {provide: NetService, useValue: netServiceSpy},
                {provide: PcrudService, useValue: pcrudServiceSpy},
                {provide: ToastService, useValue: toastServiceSpy},
                {provide: PermService, useValue: permServiceSpy},
                {provide: NgbModal, useValue: modalSpy},
            ],
            schemas: [NO_ERRORS_SCHEMA],
            imports: [NgbNav]
        }).compileComponents();
    }));

    beforeEach(() => {
        fixture = TestBed.createComponent(CourseAssociateMaterialComponent);
        component = fixture.componentInstance;
        component.confirmOtherLibraryDialog = dialogComponentSpy;
        component.currentCourse = mockCourse;
    });

    describe('#associateItem method', () => {
        afterEach(() => {
            courseServiceSpy.associateMaterials.calls.reset();
        });

        describe('item circ_lib is different from course owning lib', () => {
            it('attempts to change item circ_lib to the course\'s library', waitForAsync(() => {
                const paramsWithCircLib = {
                    barcode: '123',
                    relationship: 'required reading',
                    isModifyingLibrary: true,
                    tempLibrary: 22, // the Library that owns the course, rather than the item's circ_lib
                    currentCourse: mockCourse,
                    isModifyingCallNumber: undefined, isModifyingCircMod: undefined,
                    isModifyingLocation: undefined, isModifyingStatus: undefined,
                    tempCircMod: undefined, tempLocation: undefined, tempStatus: undefined
                };
                component.associateItem('123', 'required reading');

                setTimeout(() => { // wait for the subscribe() to do its work
                    expect(courseServiceSpy.associateMaterials).toHaveBeenCalledWith(mockItem, paramsWithCircLib);
                }, 500);
            }));

            it('asks the user to confirm', (waitForAsync(() => {
                component.associateItem('123', 'required reading');
                setTimeout(() => { // wait for the subscribe() to do its work
                    expect(dialogComponentSpy.open).toHaveBeenCalled();
                }, 500);
            })));

            it('sets the owning library\'s shortname in the UI', (waitForAsync(() => {
                component.associateItem('123', 'required reading');
                setTimeout(() => { // wait for the subscribe() to do its work
                    expect(component.itemCircLib).toBe('greatLibrary');
                }, 500);
            })));

            it('does not proceed if the user says "no" in the different library confirmation dialog', waitForAsync(() => {
                component.confirmOtherLibraryDialog = rejectedDialogComponentSpy;
                component.associateItem('123', 'required reading');

                setTimeout(() => { // wait for the subscribe() to do its work
                    expect(rejectedDialogComponentSpy.open).toHaveBeenCalled();
                    expect(courseServiceSpy.associateMaterials).not.toHaveBeenCalled();
                }, 500);
            }));

        });
    });
});
