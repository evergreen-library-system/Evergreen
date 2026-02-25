import { Component, inject } from '@angular/core';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService, PatronAlerts} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: 'alerts.component.html',
    selector: 'eg-patron-alerts',
    styleUrls: ['./alerts.component.css'],
    imports: [StaffCommonModule]
})
export class PatronAlertsComponent {
    private org = inject(OrgService);
    private net = inject(NetService);
    patronService = inject(PatronService);
    context = inject(PatronContextService);


    alerts(): PatronAlerts {
        return this.context.summary ? this.context.summary.alerts : null;
    }
}

