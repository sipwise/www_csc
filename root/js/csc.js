//////////////////////////////////
// move around destination sets //
//                              //
// needed for destinations      //
//                              //

function move_up (item) {
    var mover = $('#' + item);
    var previous = mover.prev();
    mover.insertBefore (previous);
    update_priority(item);
}

function move_down (item) {
    var mover = $('#' + item);
    var next = mover.next();
    mover.insertAfter (next);
    update_priority(item);
}
    
function update_priority(item) {
    
    var i = 1;
    var form = $('#'+item).parent().find("div form");

    $('#'+item).parent().children('.sub-container').each(function(index) {
        var id = $(this).children('form').children("[name='dtarget_id']").val();
        form.children('[name="priority-'+ id +'"]').val(index);
    });
    
    form.children('[name="priority_changed"]').val(1);
}

////////////////////////////////////////////////
// creation of period parts (year, month, ..) //
//                                            //
// get_wdays() and get_months() are in the    //
// template and return the according arrays   //
//                                            //
// create_period_part will return html, not   //
// print or                                   //
// position it                                //
//                                            //

/*
 * kind     (from|to)
 * disabled if !disabled => we're editing
 * selected which option is selected
 * name     as it should be writte in html
 *
 */
function create_period_part (kind, disabled, selected, name) { 
   
    var function_name = 'get_' + name + 's';
    var steps = window[function_name] ();

    var html = '';

    if (disabled == 1) {
        html += '<select class="dateform-elem" disabled="disabled" name="' + kind + '_' + name.toLowerCase() + '">';
    }
    else {
        html += '<select class="dateform-elem" name="' + kind + '_' + name.toLowerCase() + '">';
    }
    
    html += '<option style="text-transform:capitalize" value="-1">' + name + '</option>';

    for (var i = 0; i < steps.length; i++) {

        var value = steps[i].value;
        var label = steps[i].label;

        if (value == selected) { 
            html += '<option selected="selected" value="' + value + '">' + label + '</option>';
        }
        else {
            html += '<option value="' + value + '">' + label + '</option>';
        }
    }
    html += '</select>';
    
    return html;
}

function get_years () {
    var years = Array(); 
    var d = new Date();
    var current_year = d.getFullYear();
    
    for (var i = 0; i < 10 ; i++) {
        years.push ( {value: current_year+i, label: current_year+i} );
    }

    return years;
}

function get_mdays () { 
    var stuff = Array ();
    for (var i = 0; i < 31; i++) {
        stuff.push ( {value: i+1, label: i+1 } );
    }
    return stuff;
}

function get_hours () { 
    var stuff = Array ();
    for (var i = 0; i < 24; i++) {
        stuff.push ( {value: i, label: i } );
    }
    return stuff;
}

function get_minutes () { 
    var stuff = Array ();
    for (var i = 0; i < 60; i++) {
        stuff.push ( {value: i, label: i } );
    }
    return stuff;
}

function print_html (target, html, disabled) {
    
    $("#" + target).empty().append (html);

    if (disabled == 1) {
        $("#" + target + "-foot").empty();
    }
    else {
        $("#" + target + "-foot").empty().append('<a class="link" href="javascript:void(0)" onclick="remove_html(\'' + target + '\', \'' + disabled + '\')">Remove</a>');
    }
}

function remove_html (target, disabled) {
    
    $("#" + target).empty().append('<p>any</p>');
    $("#" + target + '-errormsg').empty().append('&nbsp;');
    
    if (disabled == 1) {
        $("#" + target + "-foot").empty();
    }
    else {
        $("#" + target + "-foot").empty().append('<a class="link" href="javascript:void(0)" onclick="put(\'' + target + '\')">Add</a>');
    }
}

function put (target) {
    
    var html;
    var part = target.substring (0, (target.indexOf('-')));
    var callback = 'get_' + part;

    html  = create_period_part ('from', 0, undefined, part, callback) 
    html += 'through<br/>';
    html += create_period_part ('to', 0, undefined, part, callback) 
    print_html (target, html, 0);
}
