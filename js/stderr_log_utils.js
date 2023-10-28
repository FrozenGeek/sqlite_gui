//////////////////////////////////////////////////////////////////////////////
// Javascript for fetching log lines whose data_id matches some data_id,
// such as 'stderr:logger:s330', and appending them to a specified target div.
//
// Typical invocation will look like:
//    <script src="/js/stderr_log_utils.js"></script>
//    <script src="/js/websocket.js"></script>
//
// Will take lines whose id matches 'stderr:logger:gyr1' and append them
// to a div on the page whose identity is 'gyr1_stderr'. Etc.

////////////////////////////

var STDERR = (function() {
    var loggers = {}

    var process = function(target, lines) {
        // target = target div
        // lines = array of {timestamp, msg}
        if (!lines || lines.length == 0) {
            return;
        }
        var new_log_lines = '';
        for (var i = 0, j = lines.length ; i < j; i++) {
            if (i > 0 && lines[i] == lines[i - 1]) {
                continue;  // skip duplicate messages
            }
            var [timestamp, log_line] = lines[i];

            // Clean up message and add to new_log_lines list
            log_line = log_line.replace(/\n$/, '');
            log_line = log_line.replace(/\n/, '<br />') ;
            new_log_lines += color_log_line(log_line, target);
        }

        // Once all log lines have been added, fetch the div where we're
        // going to put them, and add to bottom.
        if (new_log_lines.length > 0) {
            var target_div = document.getElementById(target);
            if (!target_div) {
                console.warn ('Couldn\'t find div for ' + target);
                return;
            }
            target_div.innerHTML += new_log_lines;
            // scroll to bottom
            // FIXME:  Should not do this if user is interacting with the element :-(
            //         FIGURE OUT HOW TO SET A TIMEOUT OR SOMETHING
            if (! scrolls[target_div]) {
                target_div.scrollTop = target_div.scrollHeight;
            }
            // FIFO the message, keeping an arbitrary 200
            // Otherwise we could have 10's of thousands.  Not cool.
            var count = target_div.childElementCount;
            while (count > 200) {
                target_div.removeChild(target_div.firstChild);
                count--;
            }
        }
    }

    // Add a span that includes 3 buttons,right justified.  In that,
    // three small badges. aSee if there's a text-small class
    // Badge.  Want to add these to each stderr window with count
    //         of error warning/error/criticals.
    // <span class="position-absolute top-0 start-100
    //              translate-middle badge rounded-pill bg-danger">
    // Add the d-none class, toggle that when count > 0             
    // 99+
    // </span>
    var crit = {};
    var errs = {};
    var warn = {};

    // If we abandon the screen for... let's say 2 minutes,
    // reset scroll to bottom.
    var scrolls = {};
    // FIXME:  Make configurable
    var scroll_timeout = 120000;
    function stderr_scroll(evt) {
        evt.preventDefault();
        var t = evt.target;
        var sH = t.scrollHeight;
        var sT = t.scrollTop;
        if ((sH-sT) > 60) { // We've manually scrolled
            id = t.id;
            if (scrolls[id]) {
                clearTimeout(scrolls[id]);
            }
            scrolls[id] = setTimeout(function() {reset_scroll(t)}, scroll_timeout);
        }
    }

    function reset_scroll(target) {
        console.info("Reset ", target.id, " scroll to bottom");
        target.scrollTop = target.scrollHeight;
        delete scrolls[target.id];
    }

    function create(logger) {
        var div = document.createElement('div');
        div.setAttribute('id', logger + "_stderr");
        div.className = 'stderr_window border border-dark';
        div.addEventListener('contextmenu', ctxmenu);
        div.addEventListener('scroll', stderr_scroll);
        return div;
    }

    function color_log_line (message, target) {
        var color = 'text-body';
        if (message.includes (' 30 WARNING ') > 0) {
            color = 'text-warning';
            warn[target] = warn[target] + 1 || 1;
        }
        else if (message.includes (' 40 ERROR ') > 0) {
            color = 'text-danger font-weight-bold';
            errs[target] = errs[target] + 1 || 1;
        }
        else if (message.includes (' 50 CRITICAL ') > 0) {
            color = 'text-light bg-danger';
            crit[target] = crit[target] + 1 || 1;
        }
        message = '<span class="' + color + '">' + message + '</span><br />';
        return message;
    }

    /////////////////////////////////////////////////////////////////
    //
    // Code for handling the context menu on the STDERR windows
    //
    /////////////////////////////////////////////////////////////////
    var currentContextTarget = null;
    var ctxmenu = function(evt) {
        evt.preventDefault();
        div = evt.currentTarget;
        if (div.id.endsWith('_stderr')) {
            currentContextTarget = div;
        } else {
            console.warn('Context menu on inappropriate div', div.id);
            return false;
        }
        ctx_menu_html.style.left = evt.pageX + 'px';
        ctx_menu_html.style.top = evt.pageY + 'px';
        ctx_menu_html.classList.add('menu-show');
    }

    var ctx_ack = function(evt) {
        ctx_menu_html.classList.remove('menu-show');
    }

    var ctx_clear = function(evt) {
        var d = currentContextTarget;
        while (d.lastElementChild) {
            d.removeChild(d.lastElementChild);
        }
        ctx_menu_html.classList.remove('menu-show');
    }

    var create_ctx_menu_html = function() {
        //<ul class="menu" id="context-menu">
        var ul = document.createElement('ul');
        ul.className = 'menu';
        ul.setAttribute('id', 'STDERR-context-menu');
        //<li class="menu-item">
        var li = document.createElement('menu');
        li.className = 'menu-item';
        // <a href="#" onClick="STDERR.ctx_ack()" class="menu-btn">
        var a = document.createElement('a');
        a.className = 'menu-btn';
        a.addEventListener('click', ctx_ack);
        // <span class="menu-text">Acknowlege</span>
        var sp = document.createElement('span');
        sp.className = 'menu-text';
        sp.innerHTML = 'Acknowlege';
        a.appendChild(sp);
        // </a>
        li.appendChild(a);
        // </li>
        ul.appendChild(li);
        // <li class="menu-item">
        li = document.createElement('li');
        li.className = 'menu-item';
        // <a href="#" onClick="STDERR.ctx_clear()" class="menu-btn">
        var a = document.createElement('a');
        a.className = 'menu-btn';
        a.addEventListener('click', ctx_clear);
        // <span class="menu-text">Clear</span>
        var sp = document.createElement('span');
        sp.className = 'menu-text';
        sp.innerHTML = 'Clear';
        a.appendChild(sp);
        // </li>
        li.appendChild(a);
        // </ul>
        ul.appendChild(li);
        return ul;
    }

    // only run once when function instantiates
    var ctx_menu_html = create_ctx_menu_html();
    document.body.appendChild(ctx_menu_html);

    return {
        process: process,
        create: create,
    }

})();

