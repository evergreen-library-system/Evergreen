import {Component, OnInit} from '@angular/core';
import {StaffCatalogService} from './catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';

@Component({
  templateUrl: 'catalog.component.html'
})
export class CatalogComponent implements OnInit {

    constructor(
        private basket: BasketService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        // Create the search context that will be used by all of my
        // child components.  After initial creation, the context is
        // reset and updated as needed to apply new search parameters.
        this.staffCat.createContext();
    }
}

