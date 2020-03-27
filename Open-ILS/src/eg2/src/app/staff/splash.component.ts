import {Component, OnInit, Renderer2} from '@angular/core';
import {Router} from '@angular/router';

@Component({
    templateUrl: 'splash.component.html'
})

export class StaffSplashComponent implements OnInit {

    catSearchQuery: string;

    constructor(
        private renderer: Renderer2,
        private router: Router
    ) {}

    ngOnInit() {

        // Focus catalog search form
        this.renderer.selectRootElement('#catalog-search-input').focus();
    }

    searchCatalog(): void {
        if (!this.catSearchQuery) { return; }

        this.router.navigate(
            ['/staff/catalog/search'],
            {queryParams: {query : this.catSearchQuery}}
        );
    }
}


