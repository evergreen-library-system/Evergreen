/////////////////////DATEPICKER///////////////////////////////////////////
 <div class="input-group date" data-provide="datepicker">
    <input type="text" class="form-control" name="expire_time"  value="[% expire_time | html %]" data-date-format="mm/dd/yyyy">
    <div class="input-group-addon">
        <span class="glyphicon glyphicon-th"></span>
    </div>
</div>

/////////////////////TOOLTIPS///////////////////////////////////////////
<!--HTML tags can be used in the toggletips. NOTE: we no longer use Bootstrap tooltips.-->  
 <a href="#" aria-label="Short description for screen readers" title="text to show on <b>tooltip</b>" data-toggletip>
    <i class="fas fa-question-circle" aria-hidden="true"></i>
</a>
<!--Use <a> or <button> as tooltips. They will not work on form fields or labels.-->
<!--See toggletips.js.tt2-->


