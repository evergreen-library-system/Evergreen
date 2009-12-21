{
    'NO_BRT_RESULTS': "There are no bookable resource types registered.",
    'NO_TARG_DIV': "Could not find target div",
    'NO_BRA_RESULTS': "Couldn't retrieve booking resource attributes.",
    'SELECT_A_BRSRC_THEN': "Select a resource from the big list above.",
    'CREATE_BRESV_LOCAL_ERROR': "Exception trying to create reservation: ",
    'CREATE_BRESV_SERVER_ERROR': "Server error trying to create reservation: ",
    'CREATE_BRESV_SERVER_NO_RESPONSE': "No response from server after trying " +
        "to create reservation: ",
    /* FIXME: Users aren't likely to be able to do anything with the following
     * message.  Figure out a way to do something more helpful.
     */
    'CREATE_BRESV_OK_MISSING_TARGET': function(n, m) {
        return "Created " + n + " reservation(s), but " + m + " of these " +
            "couldn't target any resources.";
    },
    'CREATE_BRESV_OK': function(n) {
        return "Created " + n + " reservation" + (n == 1 ? "" : "s") + ".";
    },
    'WHERES_THE_BARCODE': "Enter a patron's barcode to make a reservation.",
    'ACTOR_CARD_NOT_FOUND': "Patron barcode not found. Please try again.",
    'GET_BRESV_LIST_ERR': "Error while retrieving reservation list: ",
    'GET_BRESV_LIST_NO_RESULT': "No results from server " +
        "retrieving reservation list.",
    'OUTSTANDING_BRESV': "Outstanding reservations for patron",
    'UNTARGETED': "None targeted",
    'GET_PATRON_NO_RESULT': "No server response after attempting to " +
        "look up patron by barcode.",
    'HERE_ARE_EXISTING_BRESV': "Existing reservations for",
    'CXL_BRESV_SUCCESS': function(n) {
        return ("Canceled " + n + " reservation" + (n == 1 ? "" : "s") + ".");
    },
    'CXL_BRESV_FAILURE': "Error canceling reservations.",
    'CXL_BRESV_SELECT_SOMETHING': "You have not selected any reservations to " +
        "cancel.",
    'ANY': "ANY",

    'AUTO_choose_a_brt': "Choose a Bookable Resource Type",
    'AUTO_i_need_this_resource': "I need this resource...",
    'AUTO_starting_at': "Starting at",
    'AUTO_ending_at': "and ending at",
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
    'AUTO_bresv_grid_end_time': "End time"
}
