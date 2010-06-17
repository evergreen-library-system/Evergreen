    function formatPoName(po) {
        if (po) {
            return "<a href='" + oilsBasePath + "/acq/po/view/" + po.id +
                "'>" + po.name + "</a>";
        }
    }

