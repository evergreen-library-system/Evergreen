import { NgModule, Type } from '@angular/core';
import { RouterModule, Routes, Route } from '@angular/router';

/**
 * Generates a standard set of routes for bucket components
 * @param bucketComponent - The main bucket listing component
 * @param bucketItemComponent - The component for viewing bucket contents
 * @param customRoutes - Optional additional routes to include
 * @returns Routes configuration for the bucket type
 */
export function getBucketRoutes<T, U>(
  bucketComponent: Type<T>,
  bucketItemComponent: Type<U>,
  customRoutes: Route[] = []
): Routes {
  const defaultRoutes: Routes = [
    { path: '', component: bucketComponent },
    { path: 'admin', component: bucketComponent },
    { path: 'all', component: bucketComponent },
    { path: 'user', component: bucketComponent },
    { path: 'favorites', component: bucketComponent },
    { path: 'recent', component: bucketComponent },
    { path: 'shared-with-others', component: bucketComponent },
    { path: 'shared-with-user', component: bucketComponent },
    { path: 'bucket/:id', component: bucketItemComponent },
    { path: 'content/:id', component: bucketItemComponent },
    { path: ':id', component: bucketComponent }
  ];
  
  return [...defaultRoutes, ...customRoutes];
}

@NgModule({
  // Empty base module, only the function is used
})
export class BaseBucketRoutingModule {}
