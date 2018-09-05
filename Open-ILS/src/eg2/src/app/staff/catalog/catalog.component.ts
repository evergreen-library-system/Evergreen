import {Component, OnInit} from '@angular/core';
import {StaffCatalogService} from './catalog.service';

@Component({
  templateUrl: 'catalog.component.html'
})
export class CatalogComponent implements OnInit {

    constructor(private staffCat: StaffCatalogService) {}

    ngOnInit() {
        // Create the search context that will be used by all of my
        // child components.  After initial creation, the context is
        // reset and updated as needed to apply new search parameters.
        this.staffCat.createContext();
    }
}

