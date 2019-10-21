import { async, ComponentFixture, TestBed } from '@angular/core/testing';
import { NgbPopoverModule } from '@ng-bootstrap/ng-bootstrap';
import { EgHelpPopoverComponent } from './eg-help-popover.component';

describe('EgHelpPopoverComponent', () => {
  let component: EgHelpPopoverComponent;
  let fixture: ComponentFixture<EgHelpPopoverComponent>;

  beforeEach(async(() => {
    TestBed.configureTestingModule({
      declarations: [ EgHelpPopoverComponent ],
      imports: [NgbPopoverModule]
    })
    .compileComponents();
  }));

  beforeEach(() => {
    fixture = TestBed.createComponent(EgHelpPopoverComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
