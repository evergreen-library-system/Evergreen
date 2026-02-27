import { environment } from '@env/environment';
import { LocaleService } from './locale.service';
import { MockGenerators } from 'test_data/mock_generators';
import { firstValueFrom } from 'rxjs';
import { TestBed } from '@angular/core/testing';
import { PcrudService } from './pcrud.service';
import { CookieService } from 'ngx-cookie';

const orignalProductionState = environment.production;
let pcrudMock: PcrudService;

describe('LocaleService', () => {
    describe('supportedLocales()', () => {
        beforeEach(() => {
            pcrudMock = MockGenerators.pcrudService({search: [MockGenerators.idlObject({code: 'en-US'})]});
            TestBed.configureTestingModule({providers: [
                {provide: PcrudService, useValue: pcrudMock},
                {provide: Location, useValue: {}},
                {provide: CookieService, useValue: {}}
            ]});
        });
        describe('when not in a production environment', () => {
            beforeEach(() => environment.production = false);
            afterEach(() => environment.production = orignalProductionState);
            it('only retrieves en-US from the pcrud service', async () => {
                const service = TestBed.inject(LocaleService);

                await firstValueFrom(service.supportedLocales());
                expect(pcrudMock.search).toHaveBeenCalledOnceWith(
                    'i18n_l', {code: 'en-US'}, {}, {anonymous: true}
                );
            });
        });
        describe('when in a production environment', () => {
            beforeEach(() => environment.production = true);
            afterEach(() => environment.production = orignalProductionState);
            it('retrieves any staff_catalog=true locale from the pcrud service', async () => {
                const service = TestBed.inject(LocaleService);

                await firstValueFrom(service.supportedLocales());
                expect(pcrudMock.search).toHaveBeenCalledOnceWith(
                    'i18n_l', {staff_client: 't'}, {}, {anonymous: true}
                );
            });
        });
    });
});
