import { TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { FormatService } from '@eg/core/format.service';
import { IdlService } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { MockGenerators } from 'test_data/mock_generators';
import { FundingSourceTransactionsDialogComponent } from './funding-source-transactions-dialog.component';
import { LocaleService } from '@eg/core/locale.service';

let component: FundingSourceTransactionsDialogComponent;

describe('FundingSourceTransactionsDialogComponent', () => {
    beforeEach(() => {
        TestBed.configureTestingModule({providers: [
            {provide: AuthService, useValue: null},
            {provide: FormatService, useValue: {wsOrgTimezone: 'America/Vancouver'}},
            {provide: IdlService, useValue: MockGenerators.idlService({acqfs: [{name: 'fund'}]})},
            {provide: LocaleService, useValue: null},
            NgbModal,
            {provide: OrgService, useValue: null},
            {provide: PcrudService, useValue: MockGenerators.pcrudService({})},
            {provide: ToastService, useValue: null}
        ]});
        component = TestBed.createComponent(FundingSourceTransactionsDialogComponent).componentInstance;
        component.ngOnInit();
    });

    describe('cellTextGenerator', () => {
        it('contains the fund code, year, and org', () => {
            const rawData = MockGenerators.idlObject({
                fund: MockGenerators.idlObject({
                    code: 'JUV',
                    year: '2050',
                    org: MockGenerators.idlObject({shortname: 'MYLIB'})
                })
            });

            expect(component.cellTextGenerator.fund(rawData)).toEqual('JUV (2050) (MYLIB)');
        });
    });
});
