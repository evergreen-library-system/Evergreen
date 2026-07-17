import { TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { NetService } from '@eg/core/net.service';
import { MockGenerators } from 'test_data/mock_generators';
import { of } from 'rxjs';
import { ActivatedRoute } from '@angular/router';
import { ToastService } from '@eg/share/toast/toast.service';
import { IdlService } from '@eg/core/idl.service';
import { SurveyEditComponent } from './survey-edit.component';
import { LocaleService } from '@eg/core/locale.service';
import { FormatService } from '@eg/core/format.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';

describe('SurveyEditComponent', () => {
    it('Displays whether or not it is an Opac Survey', async () => {
        const mockNetService = MockGenerators.netService({
            'open-ils.circ.survey.fleshed.retrieve': of(
                MockGenerators.idlObject({
                    name: 'Fall 2040 Survey',
                    description: 'The questions we want to ask our patrons',
                    // The open-ils.circ.survey.fleshed.retrieve method uses 1 and 0
                    // to represent boolean values, unlike the 't' and 'f' that we
                    // receive from pcrud
                    opac: 1,
                    poll: 0,
                    required: 0,
                    usr_summary: 0,
                    questions: []
                })
            )
        });
        const mockIdlService = MockGenerators.idlService({
            asv: {
                fields: [
                    {name: 'id', datatype: 'id'},
                    {name: 'name', datatype: 'text'},
                    {name: 'description', datatype: 'description'},
                    {name: 'opac', datatype: 'bool'},
                    {name: 'poll', datatype: 'bool'},
                    {name: 'required', datatype: 'bool'},
                    {name: 'usr_summary', datatype: 'bool'},
                ]
            }
        });
        TestBed.configureTestingModule({
            providers: [
                {provide: ActivatedRoute, useValue: {snapshot: {paramMap: {get: () => 35}}}},
                {provide: AuthService, useValue: MockGenerators.authService()},
                {provide: FormatService, useValue: {}},
                {provide: IdlService, useValue: mockIdlService},
                {provide: LocaleService, useValue: MockGenerators.localeService()},
                {provide: NetService, useValue: mockNetService},
                {provide: OrgService, useValue: {}},
                {provide: PcrudService, useValue: {}},
                {provide: ToastService, useValue: {}},
            ]
        }).compileComponents();

        const fixture = TestBed.createComponent(SurveyEditComponent);

        // The Fieldmapper Editor relies on a lot of Promises, such that we unfortunately
        // need to run these repeatedly :-(
        fixture.detectChanges();
        await fixture.whenStable();
        fixture.detectChanges();
        await fixture.whenStable();

        expect(fixture.nativeElement.querySelector('#opac-true').checked).toBeTrue();
        expect(fixture.nativeElement.querySelector('#opac-false').checked).toBeFalse();
    });
});
