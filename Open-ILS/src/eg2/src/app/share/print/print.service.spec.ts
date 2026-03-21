import { TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { LocaleService } from '@eg/core/locale.service';
import { StoreService } from '@eg/core/store.service';
import { PrintService } from './print.service';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { firstValueFrom, lastValueFrom } from 'rxjs';

describe('PrintService', () => {
    describe('clearPrintTemplateCache', () => {
        it('sends a request to the correct endpoint', async () => {
            TestBed.configureTestingModule({providers: [
                {provide: LocaleService, useValue: null},
                {provide: AuthService, useValue: null},
                {provide: StoreService, useValue: null},
                PrintService,
                provideHttpClient(),
                provideHttpClientTesting(),
            ]});

            const service = TestBed.inject(PrintService);
            const httpTesting = TestBed.inject(HttpTestingController);

            const promise = firstValueFrom(service.clearPrintTemplateCache(12));

            const req = httpTesting.expectOne('/print_template_cache_clear', 'Request to clear the cache');
            expect(req.request.method).toBe('POST');

            const expectedBody = new FormData();
            expectedBody.append('template_owner', '12');
            expect(req.request.body).toEqual(expectedBody);

            req.flush('OK');

            await promise;

            httpTesting.verify();
        });
    });
});
