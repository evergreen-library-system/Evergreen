import { Timezone } from '@eg/share/util/timezone';
import { TimezoneSelectComponent } from './timezone-select.component';

describe('TimezoneSelectComponent', () => {
    it('should have an entry for each valid timezone', () => {
        const service = jasmine.createSpyObj<Timezone>(['values']);
        service.values.and.returnValue(['America/Vancouver']);
        const component = new TimezoneSelectComponent(service);
        expect(component.entries).toContain({id: 'America/Vancouver', label: 'America/Vancouver'});
    });
});
