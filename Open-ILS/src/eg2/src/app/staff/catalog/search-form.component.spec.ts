import { Renderer2 } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router } from '@angular/router';
import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { CatalogService } from '@eg/share/catalog/catalog.service';
import { StaffCatalogService } from './catalog.service';
import { SearchFormComponent } from './search-form.component';
import { IdlObject } from '@eg/core/idl.service';
import { CatalogSearchContext } from '@eg/share/catalog/search-context';

describe('SearchFormComponent', () => {
    let fixture;
    let component;

    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [
                Renderer2,
                { provide: Router, useValue: null },
                { provide: ActivatedRoute, useValue: null},
                { provide: OrgService, useValue: null},
                { provide: CatalogService, useValue: null},
                { provide: ServerStoreService, useValue: null},
                { provide: StaffCatalogService, useValue: null }
            ]
        }).compileComponents();
        fixture = TestBed.createComponent(SearchFormComponent);
        component = fixture.debugElement.componentInstance;
    });
    describe('orgOnChange()', () => {
        describe('when the org is actually a location group', () => {
            it('adds the expected location group search string to the context', () => {
                const location = jasmine.createSpyObj<IdlObject>(['id'], {classname: 'acplg'});
                location.id.and.returnValue(12);
                component.context = new CatalogSearchContext();

                component.orgOnChange(location);

                expect(component.context.termSearch.locationGroupOrLasso).toEqual('location_groups(12)');
            });
        });
    });
});
