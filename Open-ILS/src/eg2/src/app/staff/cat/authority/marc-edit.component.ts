import {Component, OnInit, AfterViewInit, ViewChild, Renderer2} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {MarcSavedEvent} from '@eg/staff/share/marc-edit/editor.component';

@Component({
  templateUrl: 'marc-edit.component.html'
})
export class AuthorityMarcEditComponent implements AfterViewInit {

    authorityId: number;

    // Avoid setting authorityId during lookup because it can
    // cause the marc editor to load prematurely.
    loadId: number;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private renderer: Renderer2) {
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

