import { waitForAsync } from '@angular/core/testing';
import { CourseService } from './course.service';
import { AuthService } from '@eg/core/auth.service';
import { EventService } from '@eg/core/event.service';
import { IdlService, IdlObject } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { of } from 'rxjs';

describe('CourseService', () => {
    let service: CourseService;
    let circLib = 5;
    let originalCircLib: number;

    const mockCallNumber = {
        label_class: () => 1,
        prefix: () => 2,
        suffix: () => null ,
        owning_lib: () => 5,
        record: () => 123
    };

    const materialSpy = jasmine.createSpyObj<IdlObject>(['item', 'record', 'course', 'original_circ_lib']);
    materialSpy.original_circ_lib.and.callFake((newValue?: number) => {
        if (newValue) {
            originalCircLib = newValue;
        } else {
            return originalCircLib;
        }
    });
    const itemSpy = jasmine.createSpyObj<IdlObject>(['call_number', 'circ_lib', 'id']);
    itemSpy.circ_lib.and.callFake((newValue?: number) => { // this will return 5 unless set otherwise
        if (newValue) {
            circLib = newValue;
        } else {
            return circLib;
        }
    });
    itemSpy.call_number.and.returnValue(mockCallNumber);
    const authServiceSpy = jasmine.createSpyObj<AuthService>(['token']);
    authServiceSpy.token.and.returnValue('myToken');
    const evtServiceSpy = jasmine.createSpyObj<EventService>(['parse']);
    const idlServiceSpy = jasmine.createSpyObj<IdlService>(['create']);
    idlServiceSpy.create.and.returnValue(materialSpy);
    const netServiceSpy = jasmine.createSpyObj<NetService>(['request']);
    netServiceSpy.request.and.returnValue(of());
    const orgServiceSpy = jasmine.createSpyObj<OrgService>(['settings', 'canHaveVolumes']);
    const pcrudServiceSpy = jasmine.createSpyObj<PcrudService>(['retrieveAll', 'search', 'update', 'create']);
    pcrudServiceSpy.update.and.returnValue(of(1));
    pcrudServiceSpy.create.and.returnValue(of(materialSpy));

    const mockOrg = {
        a: [],
        classname: 'aou',
        _isfieldmapper: true,
        id: () => 5
    };

    const mockConsortium = {
        id: () => 1
    };

    const mockCourse = {
        id: () => 20
    };

    beforeEach(() => {
        service = new CourseService(authServiceSpy, evtServiceSpy,
            idlServiceSpy, netServiceSpy,
            orgServiceSpy, pcrudServiceSpy);
        orgServiceSpy.canHaveVolumes.and.returnValue(true);
        circLib = 5; // set the item's circ lib to 5
    });

    afterEach(() => {
        pcrudServiceSpy.update.calls.reset();
        itemSpy.circ_lib.calls.reset();
        materialSpy.original_circ_lib.calls.reset();
    });

    it('updateItem() passes the expected parameters to open-ils.cat', () => {
        service.updateItem(itemSpy, mockOrg, 'ABC 123', true);
        expect(netServiceSpy.request).toHaveBeenCalledWith(
            'open-ils.cat', 'open-ils.cat.call_number.find_or_create',
            'myToken', 'ABC 123', 123, 5, 2, null, 1
        );
    });

    it('updateItem() calls pcrud only once when modifying call number', () => {
        service.updateItem(itemSpy, mockOrg, 'ABC 123', true);
        expect(pcrudServiceSpy.update).toHaveBeenCalledTimes(1);
    });

    it('updateItem() calls pcrud only once when not modifying call number', () => {
        service.updateItem(itemSpy, mockOrg, 'ABC 123', false);
        expect(pcrudServiceSpy.update).toHaveBeenCalledTimes(1);
    });

    it('#associateMaterials can temporarily change the item circ_lib', waitForAsync(() => {
        const results = service.associateMaterials(itemSpy, {tempLibrary: 4, isModifyingLibrary: true, currentCourse: mockCourse});
        expect(results.item.circ_lib()).toBe(4);
        results.material.then((material) => {
            expect(material.original_circ_lib()).toBe(5);
        });
    }));

    it('#associateMaterials does not change the item circ_lib if the requested lib can\'t have items', () => {
        orgServiceSpy.canHaveVolumes.and.returnValue(false);
        const results = service.associateMaterials(itemSpy, {tempLibrary: 1, isModifyingLibrary: true, currentCourse: mockCourse});
        expect(itemSpy.circ_lib).not.toHaveBeenCalled();
        expect(results.item.circ_lib()).toBe(5);
        expect(materialSpy.original_circ_lib).not.toHaveBeenCalled();
    });

});
