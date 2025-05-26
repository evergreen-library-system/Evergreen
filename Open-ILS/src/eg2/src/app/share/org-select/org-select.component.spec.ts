import { ComponentFixture, TestBed } from '@angular/core/testing';
import { OrgSelectComponent } from './org-select.component';
import { AuthService } from '@eg/core/auth.service';
import { MockGenerators } from 'test_data/mock_generators';
import { ServerStoreService } from '@eg/core/server-store.service';
import { OrgService } from '@eg/core/org.service';

describe('OrgSelectComponent', () => {
    let fixture: ComponentFixture<OrgSelectComponent>;
    beforeEach(() => {
        const root = MockGenerators.idlObject({id: '1', shortname: 'LINN', ou_type: MockGenerators.idlObject({depth: 1})});
        const mockOrg = jasmine.createSpyObj<OrgService>(['list', 'sortTree', 'absorbTree']);
        mockOrg.list.and.returnValue([root]);
        TestBed.configureTestingModule({
            providers: [
                {provide: AuthService, useValue: MockGenerators.authService()},
                {provide: ServerStoreService, useValue: MockGenerators.serverStoreService(false)},
                {provide: OrgService, useValue: mockOrg}
            ],
        });
        fixture = TestBed.createComponent(OrgSelectComponent);
        fixture.detectChanges();
    });
    it('can create without error', () => {
        expect(fixture.componentInstance).toBeTruthy();
    });
});
