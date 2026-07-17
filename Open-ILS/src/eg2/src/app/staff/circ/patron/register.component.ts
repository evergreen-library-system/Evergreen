import { Component, OnInit, inject } from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { EditComponent } from './edit.component';
import { EditToolbarComponent } from './edit-toolbar.component';
import { WorkLogStringsComponent } from '@eg/staff/share/worklog/strings.component';

@Component({
    templateUrl: 'register.component.html',
    imports: [
        EditComponent,
        EditToolbarComponent,
        StaffCommonModule,
        WorkLogStringsComponent
    ]
})
export class RegisterPatronComponent implements OnInit {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private evt = inject(EventService);
    private net = inject(NetService);
    private auth = inject(AuthService);
    private org = inject(OrgService);
    private pcrud = inject(PcrudService);
    private ngLocation = inject(Location);
    private patronService = inject(PatronService);
    private context = inject(PatronContextService);


    stageUsername: string;
    cloneId: number;

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.stageUsername = params.get('stageUsername');
            this.cloneId = +params.get('cloneId');
        });
    }
}

