import { TestBed } from '@angular/core/testing';
import { OrgService } from '@eg/core/org.service';
import { MockGenerators } from 'test_data/mock_generators';
import { PatronSummaryComponent } from './summary.component';
import { PrintService } from '@eg/share/print/print.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { PatronService, PatronSummary } from './patron.service';
import { PatronModule } from './patron.module';
import { provideRouter } from '@angular/router';

describe('PatronSummaryComponent', () => {
    it('shows group overdues if other group members have overdues', () => {
        TestBed.configureTestingModule({
            providers: [
                provideRouter([]),
                { provide: OrgService, useValue: MockGenerators.orgService() },
                { provide: PatronService, useValue: MockGenerators.patronService() },
                { provide: PrintService, useValue: null },
                { provide: ServerStoreService, useValue: MockGenerators.serverStoreService(false) }
            ],
            imports: [ PatronModule ]
        });
        const fixture = TestBed.createComponent(PatronSummaryComponent);
        const summary = new PatronSummary();
        summary.stats.checkouts.group.overdue = 12;
        summary.patron = MockGenerators.patron();
        fixture.componentInstance.summary = summary;

        fixture.detectChanges();

        expect(fixture.nativeElement.innerText).toMatch(/Group Overdue\s+12/);
    });
});
