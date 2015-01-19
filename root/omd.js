/* show hide specific types of reports */
var last_view_typ;
function omd_view(typ) {
    if(typ == undefined) {
        typ = last_view_typ;
    }
    last_view_typ = typ;

    if(typ == 'all') {
        jQuery('#statusTable TR').each(function(nr, el) {
            jQuery(el).removeClass('tab_hidden');
        });
    } else {
        jQuery('#statusTable TR').each(function(nr, el) {
            if(nr > 0) {
                if(jQuery(el).hasClass(typ)) {
                    jQuery(el).removeClass('tab_hidden');
                } else {
                    jQuery(el).addClass('tab_hidden');
                }
            }
        });
    }
    set_hash(typ, 1);

    jQuery('A.omdlinks').each(function(nr, link) {
        var tmp   = link.href.replace(/tab=.*/g, 'tab='+typ);
        link.href = tmp;
    });

    // make nice background colours
    reset_table_row_classes('statusTable', 'statusOdd', 'statusEven');

    // show countrys
    var last_country = "";
    jQuery('TABLE#statusTable TR').each(function(i, row) {
        if(i == 0) {
            // skip header row
            return true;
        }
        if(jQuery(row).hasClass('tab_hidden') || jQuery(row).hasClass('filter_hidden')) {
            // skip hidden rows
            return true;
        }
        country = jQuery(row).find('SPAN').first().html();
        if(country != last_country) {
            jQuery(row).find('SPAN').first().css('display', 'inherit');
            last_country = country;
        } else {
            jQuery(row).find('SPAN').first().css('display', 'none');
        }
        return true;
    });
    return true;
}
