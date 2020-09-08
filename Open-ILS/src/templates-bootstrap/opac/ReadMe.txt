/////////////////////DATEPICKER///////////////////////////////////////////
 <div class="input-group date" data-provide="datepicker">
    <input type="text" class="form-control" name="expire_time"  value="[% expire_time | html %]" data-date-format="mm/dd/yyyy">
    <div class="input-group-addon">
        <span class="glyphicon glyphicon-th"></span>
    </div>
</div>

/////////////////////TOOLTIPS///////////////////////////////////////////
<!--data-html allows use of HTML tags in the tooltip-->  
 <a href="#" title="text to show on tooltip" data-html="true" data-toggle="tooltip">
    <i class="fas fa-question-circle" aria-hidden="true"></i>
</a>
<!--This is needed to activate the tooltips on the page and is activated Globally by default in js.tt2-->
<script>
jQuery(document).ready(function(){
  jQuery('[data-toggle="tooltip"]').tooltip();
});
</script>

