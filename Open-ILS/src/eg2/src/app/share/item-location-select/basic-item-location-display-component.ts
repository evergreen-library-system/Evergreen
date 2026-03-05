import { Component, inject, Input } from '@angular/core';
import { OrgService } from '@eg/core/org.service';
import { ItemLocationService } from './item-location.service';
import { map, Observable } from 'rxjs';
import { IdlObject } from '@eg/core/idl.service';
import { AsyncPipe } from '@angular/common';
import { ParenthesesPipe } from '../pipes/parentheses_pipe';

// This component provides a simple text display of an item shelving location
// using data from the ItemLocationService
@Component({
    selector: 'eg-basic-item-location-display',
    standalone: true,
    template: '{{ locationName | async }} {{ orgName | async | parentheses }}',
    imports: [AsyncPipe, ParenthesesPipe]
})
export class BasicItemLocationDisplayComponent {
    private loc = inject(ItemLocationService);
    private org = inject(OrgService);

    @Input() locationId: number;

    protected get locationName(): Observable<string> {
        return this.location.pipe(map((location: IdlObject) => location.name()));
    }

    protected get orgName(): Observable<string> {
        return this.location
            .pipe(map((location: IdlObject) => this.org.get(location.owning_lib())?.shortname()));
    }

    private get location(): Observable<IdlObject> {
        return this.loc.getById(this.locationId);
    }
}
