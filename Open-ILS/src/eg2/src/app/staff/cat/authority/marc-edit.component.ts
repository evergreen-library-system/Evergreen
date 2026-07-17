import { Component, AfterViewInit, Renderer2, inject } from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import { MarcEditorComponent } from '@eg/staff/share/marc-edit/editor.component';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';
import { FormsModule } from '@angular/forms';

@Component({
    templateUrl: 'marc-edit.component.html',
    imports: [
        MarcEditorComponent,
        StaffBannerComponent,
        FormsModule
    ]
})
export class AuthorityMarcEditComponent implements AfterViewInit {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private renderer = inject(Renderer2);


    authorityId: number;

    // Avoid setting authorityId during lookup because it can
    // cause the marc editor to load prematurely.
    loadId: number;

    constructor() {
        this.authorityId = +this.route.snapshot.paramMap.get('id');
    }

    ngAfterViewInit() {
        if (!this.authorityId) {
            this.renderer.selectRootElement('#auth-id-input').focus();
        }
    }

    goToAuthority() {
        if (this.loadId) {
            this.router.navigate([`/staff/cat/authority/edit/${this.loadId}`]);
        }
    }
}

