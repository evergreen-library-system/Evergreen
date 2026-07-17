import { Component, Input, OnInit, DoCheck, inject } from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlService} from '@eg/core/idl.service';
import {VolCopyContext} from './volcopy';
import {VolCopyService} from './volcopy.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    selector: 'eg-volcopy-config',
    templateUrl: 'config.component.html',
    imports: [StaffCommonModule]
})
export class VolCopyConfigComponent implements OnInit, DoCheck {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private idl = inject(IdlService);
    volcopy = inject(VolCopyService);


    @Input() context: VolCopyContext;

    defaultsCopy: any;

    ngOnInit() {
        console.debug('DEFAULTS', this.volcopy.defaults);

        // Not an IDL object, but clones just the same
        this.defaultsCopy = this.idl.clone(this.volcopy.defaults);
    }

    // Watch for changes in the form and auto-save them.
    ngDoCheck() {
        const hidden = this.volcopy.defaults.hidden;
        for (const key in hidden) {
            if (hidden[key] !== this.defaultsCopy.hidden[key]) {
                this.save();
                return;
            }
        }

        const values = this.volcopy.defaults.values;
        for (const key in values) {
            if (values[key] !== this.defaultsCopy.values[key]) {
                this.save();
                return;
            }
        }
    }

    save() {
        this.volcopy.saveDefaults().then(_ =>
            this.defaultsCopy = this.idl.clone(this.volcopy.defaults)
        );
    }
}


