{
    'NO_BRT_RESULTS': "There are no bookable resource types registered.",
    'NO_TARG_DIV': "Could not find target div",
    'NO_BRA_RESULTS': "Couldn't retrieve booking resource attributes.",
    'SELECT_A_BRSRC_THEN': "Select a resource from the big list above.",
    'CREATE_BRESV_LOCAL_ERROR': "Exception trying to create reservation: ",
    'CREATE_BRESV_SERVER_ERROR': "Server error trying to create reservation: ",
    'CREATE_BRESV_SERVER_NO_RESPONSE':
        "No response from server after trying to create reservation: ",
    /* FIXME: Users aren't likely to be able to do anything with the following
     * message.  Figure out a way to do something more helpful.
     */
    'CREATE_BRESV_OK_MISSING_TARGET': function(n, m) {
        return "Created " + n + " reservation(s), but " + m + " of these " +
            "couldn't target any resources.\n\n" +
            "This means that it won't be possible to fulfill some of these\n" +
            "reservations until a suitable resource becomes available.";
    },
    'CREATE_BRESV_OK': function(n) {
        return "Created " + n + " reservation" + (n == 1 ? "" : "s") + ".";
    },
    'WHERES_THE_BARCODE': "Enter a patron's barcode to make a reservation.",
    'ACTOR_CARD_NOT_FOUND': "Patron barcode not found. Please try again.",
    'GET_BRESV_LIST_ERR': "Error while retrieving reservation list: ",
    'GET_BRESV_LIST_NO_RESULT':
        "No results from server retrieving reservation list.",
    'OUTSTANDING_BRESV': "Outstanding reservations for patron",
    'UNTARGETED': "None targeted",
    'GET_PATRON_NO_RESULT':
        "No server response after attempting to look up patron by barcode.",
    'HERE_ARE_EXISTING_BRESV': "Existing reservations for",
    'NO_EXISTING_BRESV': "This user has no existing reservations at this time.",
    'NO_USABLE_BRSRC':
        "No reservable resources.  Adjust start and end time\n" +
        "until a resource is available for reservation.",
    'CXL_BRESV_SUCCESS': function(n) {
        return ("Canceled " + n + " reservation" + (n == 1 ? "" : "s") + ".");
    },
    'CXL_BRESV_FAILURE': "Error canceling reservations.",
    'CXL_BRESV_SELECT_SOMETHING':
        "You have not selected any reservations to cancel.",
    'NEED_EXACTLY_ONE_BRT_PASSED_IN':
        "Can't book multiple resource types at once",
    'COULD_NOT_RETRIEVE_BRT_PASSED_IN':
        "Error retrieving booking resource type",
    'INVALID_TS_RANGE':
        "You must choose a valid start and end time for the reservation.",
    'BRSRC_NOT_FOUND': "Could not locate that resource.",
    'BRSRC_RETRIVE_ERROR': "Error retrieving resource: ",
    'ANY': "ANY",

    'AUTO_choose_a_brt': "Choose a Bookable Resource Type",
    'AUTO_i_need_this_resource': "I need this resource...",
    'AUTO_starting_at': "Between",
    'AUTO_ending_at': "and",
    'AUTO_with_these_attr': "With these attributes:",
    'AUTO_patron_barcode': "Reserve to patron barcode:",
    'AUTO_ATTR_VALUE_next': "Next",
    'AUTO_ATTR_VALUE_reserve_brsrc': "Reserve Selected",
    'AUTO_ATTR_VALUE_reserve_brt': "Reserve Any",
    'AUTO_ATTR_VALUE_button_edit_existing': "Edit selected",
    'AUTO_ATTR_VALUE_button_cancel_existing': "Cancel selcted",
    'AUTO_bresv_grid_type': "Type",
    'AUTO_bresv_grid_resource': "Resource",
    'AUTO_bresv_grid_start_time': "Start time",
    'AUTO_bresv_grid_end_time': "End time",
    'AUTO_brt_noncat_only': "Show only non-cataloged bookable resource types",
    'AUTO_arbitrary_resource':
        "Enter the barcode of a cataloged, bookable resource:",
    'AUTO_explain_bookable':
        "To reserve an item that is not yet registered as a bookable " +
        "resource, find it in the catalog or under <em>Display Item</em>, and "+
        "select <em>Make Item Bookable</em> or <em>Book Item Now</em> there.",
    'AUTO_or': '- Or -'
}
