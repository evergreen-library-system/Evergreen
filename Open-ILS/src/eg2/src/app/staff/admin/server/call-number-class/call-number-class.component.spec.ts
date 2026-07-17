import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CallNumberClassComponent } from './call-number-class.component';
import { PcrudService } from '@eg/core/pcrud.service';
import { MockGenerators } from 'test_data/mock_generators';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ToastService } from '@eg/share/toast/toast.service';
import { TranslateComponent } from '@eg/share/translate/translate.component';

describe('CallNumberClassComponent', () => {
    let component: CallNumberClassComponent;
    let fixture: ComponentFixture<CallNumberClassComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [CallNumberClassComponent],
            providers: [
                {provide: PcrudService, useValue: MockGenerators.pcrudService({
                    retrieveAll: [[
                        MockGenerators.idlObject({
                            id: 2, name: 'Dewey (DDC)', normalizer: 'asset.label_normalizer_dewey', field: '080ab,082ab'
                        }),
                        MockGenerators.idlObject({
                            id: 5, name: 'Library of Congress (LC)', normalizer: 'asset.label_normalizer_lc', field: '050ab'
                        })
                    ]]
                },
                )},
                {provide: ToastService, useValue: {}}
            ],
            schemas: [CUSTOM_ELEMENTS_SCHEMA],
        }).compileComponents();

        TestBed.overrideComponent(CallNumberClassComponent, {
            remove: {imports: [TranslateComponent]},
            add: {schemas: [CUSTOM_ELEMENTS_SCHEMA]}
        });
        fixture = TestBed.createComponent(CallNumberClassComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('displays the labels of the configured classifications', async () => {
        await fixture.whenStable();
        fixture.detectChanges();
        expect(fixture.nativeElement.textContent).toContain('Dewey (DDC)');
        expect(fixture.nativeElement.textContent).toContain('Library of Congress (LC)');
    });
});
