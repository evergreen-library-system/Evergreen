import { Component, inject } from '@angular/core';
import {PatronService, PatronAlerts} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import { DatePipe } from '@angular/common';

@Component({
    templateUrl: 'alerts.component.html',
    selector: 'eg-patron-alerts',
    imports: [DatePipe]
})
export class PatronAlertsComponent {
    patronService = inject(PatronService);
    context = inject(PatronContextService);

    alerts(): PatronAlerts {
        return this.context.summary ? this.context.summary.alerts : null;
    }
}

