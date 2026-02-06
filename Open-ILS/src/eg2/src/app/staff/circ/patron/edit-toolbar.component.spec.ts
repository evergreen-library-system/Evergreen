import { ComponentFixture, TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { MockGenerators } from 'test_data/mock_generators';
import { EditToolbarComponent } from './edit-toolbar.component';

let fixture: ComponentFixture<EditToolbarComponent>;
let component: EditToolbarComponent;

describe('EditToolbarComponent', () => {
    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [
                {provide: IdlService, useValue: MockGenerators.idlService({})},
                {provide: NetService, useValue: MockGenerators.netService({})},
                {provide: ServerStoreService, useValue: MockGenerators.serverStoreService(false)},
                {provide: AuthService, useValue: MockGenerators.authService}
            ],
            declarations: [
                EditToolbarComponent
            ]
        });
    });
    it('has enabled buttons for `Suggested fields` and `Required fields`', () => {
        TestBed.configureTestingModule({
            providers: [
                {provide: ServerStoreService, useValue: MockGenerators.serverStoreService(false)},
            ]
        }).compileComponents();
        fixture = TestBed.createComponent(EditToolbarComponent);
        component = fixture.componentInstance;
        const enabledButtons = Array.from(fixture.nativeElement.querySelectorAll('button:not(:disabled)'))
            .map((button: HTMLButtonElement) => button.textContent);
        expect(enabledButtons).toContain('Required Fields', 'Suggested Fields');
    });
    it('has enabled buttons for `Required fields` and `All fields` if Suggested fields is the default', () => {
        TestBed.configureTestingModule({
            providers: [
                {provide: ServerStoreService, useValue: MockGenerators.serverStoreService(true)},
            ]
        }).compileComponents();
        fixture = TestBed.createComponent(EditToolbarComponent);
        component = fixture.componentInstance;
        const enabledButtons = Array.from(fixture.nativeElement.querySelectorAll('button:not(:disabled)'))
            .map((button: HTMLButtonElement) => button.textContent);
        expect(enabledButtons).toContain('Required Fields', 'All Fields');
    });
});
