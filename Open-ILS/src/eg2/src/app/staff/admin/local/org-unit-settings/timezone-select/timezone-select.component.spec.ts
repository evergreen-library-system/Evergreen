import { Timezone } from '@eg/share/util/timezone';
import { TimezoneSelectComponent } from './timezone-select.component';
import { TestBed } from '@angular/core/testing';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';

describe('TimezoneSelectComponent', () => {
    it('should have an entry for each valid timezone', () => {
        const service = jasmine.createSpyObj<Timezone>(['values']);
        service.values.and.returnValue(['America/Vancouver']);
        const component = TestBed
            .configureTestingModule({providers: [{provide: Timezone, useValue: service}]})
            .overrideComponent(TimezoneSelectComponent, {add: {schemas: [CUSTOM_ELEMENTS_SCHEMA]}, remove: {imports: [ComboboxComponent]}})
            .createComponent(TimezoneSelectComponent)
            .componentInstance;
        expect(component.entries).toContain({id: 'America/Vancouver', label: 'America/Vancouver'});
    });
});
