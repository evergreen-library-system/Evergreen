import { ComponentFixture, TestBed } from '@angular/core/testing';
import { AccessKeyInfoComponent } from './accesskey-info.component';
import { AccessKeyAssignment, AccessKeyService } from './accesskey.service';
import { NgbModal, NgbModalOptions } from '@ng-bootstrap/ng-bootstrap';
import { DialogComponent } from '../dialog/dialog.component';
import { of } from 'rxjs';

const mockAssignment = (
    partial: Partial<Omit<AccessKeyAssignment, 'action'>> = {}
): Omit<AccessKeyAssignment, 'action'> => ({
    key: 'ctrl+a', desc: 'Do something', ctx: 'base',
    ...partial
});

describe('AccessKeyInfoComponent', () => {
    let component: AccessKeyInfoComponent;
    let fixture: ComponentFixture<AccessKeyInfoComponent>;

    const keyServiceSpy = jasmine.createSpyObj<AccessKeyService>(['infoIze']);
    const modalSpy = jasmine.createSpyObj<NgbModal>(['open']);

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            providers: [
                { provide: AccessKeyService, useValue: keyServiceSpy },
                { provide: NgbModal, useValue: modalSpy }
            ],
            imports: [AccessKeyInfoComponent]
        }).compileComponents();

        fixture = TestBed.createComponent(AccessKeyInfoComponent);
        component = fixture.componentInstance;
        keyServiceSpy.infoIze.calls.reset();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    describe('open', () => {
        it('populates assignments when opened', () => {
            const assignments = [
                mockAssignment(),
                mockAssignment({
                    key: 'ctrl+b',
                    ctx: 'AccessKeyInfo Dialog',
                    desc: 'Do something else'
                })
            ];
            keyServiceSpy.infoIze.and.returnValue(assignments);
            spyOn(DialogComponent.prototype, 'open').and.returnValue(of(null));

            component.open();
            expect(component['assignments']).toEqual(assignments);
        });

        it('refreshes assignments when opened', () => {
            const mock1 = mockAssignment();
            const mock2 = mockAssignment({
                key: 'ctrl+b',
                ctx: 'AccessKeyInfo Dialog',
                desc: 'Do something else'
            });
            keyServiceSpy.infoIze.and.returnValues([mock1], [mock2]);
            spyOn(DialogComponent.prototype, 'open').and.returnValue(of(null));

            component.open();
            expect(component['assignments']).toEqual([mock1]);

            component.open();
            expect(component['assignments']).toEqual([mock2]);
            expect(keyServiceSpy.infoIze).toHaveBeenCalledTimes(2);
        });

        it('calls super.open with provided options', () => {
            keyServiceSpy.infoIze.and.returnValue([]);
            const openSpy = spyOn(DialogComponent.prototype, 'open').and.returnValue(of(null));
            const options: NgbModalOptions = { backdrop: 'static' };

            component.open(options);
            expect(openSpy).toHaveBeenCalledWith(options);
        });
    });
});
