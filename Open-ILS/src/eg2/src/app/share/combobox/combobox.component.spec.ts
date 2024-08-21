import { ComponentFixture, TestBed, fakeAsync, flush, discardPeriodicTasks } from '@angular/core/testing';
import { ComboboxComponent } from './combobox.component';
import { FormsModule } from '@angular/forms';
import { NgbTypeaheadModule } from '@ng-bootstrap/ng-bootstrap';
import { IdlService } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import { MockGenerators } from 'test_data/mock_generators';

const mockData = MockGenerators.idlObject({ code: 'DEFAULT', name: 'Default' });
const pcrudMock = MockGenerators.pcrudService({search: mockData});

describe('ComboboxComponent', () => {
    let component: ComboboxComponent;
    let fixture: ComponentFixture<ComboboxComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [FormsModule, NgbTypeaheadModule],
            declarations: [ ComboboxComponent ],
            providers: [
                { provide: IdlService, useValue: MockGenerators.idlService({ ccm: { pkey: 'code' } }) },
                { provide: PcrudService, useValue: pcrudMock },
                { provide: OrgService, useValue: {} }
            ]
        })
            .compileComponents();
    });

    beforeEach(() => {
        fixture = TestBed.createComponent(ComboboxComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('does not include an aria-labelledby if it is not provided', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.hasAttribute('aria-labelledby')).toBeFalse();
    });

    it('should include an aria-labelledby if it is provided', () => {
        component.ariaLabelledby = 'someElementId';
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('input[aria-labelledby="someElementId"]')).toBeTruthy();
    });

    describe('after an entry has been selected', () => {
        beforeEach(fakeAsync(() => {
            component.entries = [
                {id: 'cat', label: 'Cat'},
                {id: 'dog', label: 'Dog'}
            ];
            fixture.nativeElement.querySelector('input').click();
            flush();

            // Click on Cat from the dropdown
            fixture.debugElement.query(
                debugEl => debugEl.nativeElement.textContent === 'Cat'
            ).nativeElement.click();

            fixture.detectChanges();
        }));
        it('is available through the selectedId getter', () => {
            expect(component.selectedId).toEqual('cat');
        });
        it('is displayed in the input', () => {
            expect(fixture.nativeElement.querySelector('input').value).toEqual('Cat');
        });
        it('propagates the change (e.g. to ngModel) when you clear the field and blur', fakeAsync(() => {
            component.propagateChange = (value: any) => {};
            spyOn(component, 'propagateChange');

            // @ts-ignore -- selected can sometimes be a string, although we have it
            // typed as a ComboboxEntry
            component.selected = '';
            component.onBlur(new window.Event('blur'));

            expect(component.propagateChange).toHaveBeenCalledWith(null);
        }));
    });

    describe('default asyncDataSource', () => {
        it('should set asyncDataSource correctly', (done: DoneFn) => {
            component.idlClass = 'ccm';
            component.idlField = 'name';

            component.ngOnInit();
            component.addAsyncEntries('term').subscribe({
                complete: () => {
                    expect(pcrudMock.search).toHaveBeenCalledWith(
                        component.idlClass,
                        {
                            name: { 'ilike': '%term%' },
                        },
                        {
                            order_by: { ccm: 'name' },
                            limit: 100,
                        }
                    );
                    expect(component.entrylist.length).toEqual(1);
                    expect(component.entrylist).toEqual([{id: 'DEFAULT', label: 'Default', fm: mockData}]);
                    done();
                }
            });
        });
        it('adds a null entry if unsetString @Input is supplied', (done: DoneFn) => {
            component.idlClass = 'ccm';
            component.idlField = 'name';
            component.unsetString = '<Unset>';

            component.ngOnInit();
            component.addAsyncEntries('term').subscribe({
                complete: () => {
                    expect(component.entrylist.length).toEqual(2);
                    expect(component.entrylist).toContain({id: 'DEFAULT', label: 'Default', fm: mockData});
                    expect(component.entrylist).toContain({id: null, label: '<Unset>'});
                    done();
                }
            });
        });

    });
});
