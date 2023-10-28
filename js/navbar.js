//////////////////////////////////////////////////////////////////////////////
// Javascript for the 'head.html' stub included in all (most) of
// the webpages presented to the public.
//
// includes functions for theme switcher and
// handles the login/logout form
//



//
//  LoginButton 
//
//  Purpose:
//      Manage "Log In" button and cache auth information.
//
//  On page load checks for expired auth.  We won't check again until
//  next page load, but the CGI's may (or may not) worry about expired
//  auth, and even (roadmap) provide updated auth tokens.
//
//  NOTE:  Look into WebAuthn (fingerprint, etc)
//  
var LoginButton = (function() {

    var button = document.getElementById('login_button');

    // on_load() ==> (nothing)
    //
    // Called by body_load() to decorate the Login button 
    // Auth is in the form a a JSON Web Token.  See https://jwt.io 
    var on_load = function() {
        var jwt = localStorage.getItem('jwt_token');
        if (jwt) {
            try {
                var username = check_jwt(jwt);
                logged_in(username);
            } catch (error) {
                iziToast.warning({
                    title: 'Auth token problem',
                    message: error,
                });
                //console.warn(error);
                logged_out();
            }
        } else {
            logged_out();
        }
    };

    // We only use a couple fields in our JWT payload 
    // exp: expiration time after which token is invalid
    //      for us, that's 90 days after you log in.
    // iat: issued at time
    // name: username.
    var check_jwt = function(jwt) {
        // only one part of the JWT is not encyrpted.  Get it.
        var payload_obj;
        var s = jwt.split('.');
        if (s.length < 2) {
            throw new Error("Invalid token (lacking dots): " + jwt);
        }
        // We appear to have a payload.  Try it.
        var dec = atob(s[1]);
        try {
            payload_obj = JSON.parse(dec);
        } catch(error) {
            throw new Error("Invalid token (indeciferable): " + dec);
        }
        // Check for expired token
        if (!payload_obj.exp) { 
            throw new Error("Invalid token (No expiration time)");
        }
        var exp = new Date(payload_obj.exp * 1000);
        if (exp < Date.now()) {
            throw new Error("Login Expired.  Log in again");
        }
        // Check for a name in the payload
        if (!payload_obj.name) {
            throw new Error("Invalid token (no name)");
        }
        return payload_obj.name;
    };

    // No JWT or JWT invalid (so not logged in)
    var logged_out = function() {
        if (button) {
            button.innerHTML = 'Log In';
        }
        var el = document.getElementById('login_action');
        if (el) {
            el.setAttribute('value', 'login');
        }
        localStorage.removeItem('jwt_token');
        el = document.getElementById('login_submit_button');
        if (el) {
            el.innerHTML = 'Log In';
        }
        el = document.getElementById('config_operations');
        if (el) {
            el.classList.add('disabled');
        }
    };

    // The submit button was pressed (to log in, or log otu)
    var pressed = async function(evt, form) {
        // Keep it from navigating to the action url.
        evt.preventDefault();
        var el = document.getElementById('login_action');
	action = el.getAttribute('value');
        if (action == 'logout') {
            logged_out();
            return false;
        }
        options = {
            body: new FormData(form)
        };
        try {
            response = await Ajax('post', form.action, options);
        } catch (error) {
            iziToast.error({
                title: 'Error logging in',
                message: error,
            });
            // console.error(error);
            return false;
        }
        try {
            obj = JSON5.parse(response);
        } catch (error) {
            iziToast.error({
                title: 'JSON error',
                message: error,
            });
            // console.error(response, error);
            return false;
        }
        if (obj.jwt) {
            try {
                var username = check_jwt(obj.jwt);
                localStorage.setItem('jwt_token', obj.jwt);
                logged_in(username);
            } catch (error) {
                logged_out();
                iziToast.error({
                    title: 'Token Error',
                    message: error,
                });
            }
        }
    };

    var logged_in = function(name) {
        var el = document.getElementById('login_action');
	if (el) {
	    el.setAttribute('value', 'logout');
	}
        if (button) {
            button.innerHTML = name;
        }
        el = document.getElementById('login_submit_button');
        if (el) {
            el.innerHTML = 'Log Out';
        }
        el = document.getElementById('config_operations');
        if (el) {
            el.classList.remove('disabled');
        }
    };

    // Execute this when object loaded
    on_load();

    return {
        pressed: pressed,
    };

})();

////////////////////////////////////////////////////////////////////////////
//
//  Theme
//
//      Class to handle the themes.
//      Exports two functions:
//      - on_load - Loads the initial theme (if any)
//      - change  - Tries to change the theme to supplied option
//
var Theme = (function() {

    var css_el = document.getElementById('theme-css');

    var on_load = function() {
        // Allow config to over-ride stored theme on startup
        var o = odas || {};
        var oT = o.Themes || {};
        var theme = oT.theme || localStorage.getItem('theme');

        if (theme) {
            change(theme);
        }
 
        // NOTE: Should add an option to hide theme selector
        if (oT.HideThemes) {
            var el = document.getElementById('theme_dropdown');
            el.classList.add('d-none');
        }
    };

    var change = function(theme) {
        if (!css_el) { return; }
        var url = '/js/themes/' + theme + '/bootstrap.min.css';
        url += '?' + Date.now();
        css_el.setAttribute('href', url);
        localStorage.setItem('theme', theme);
    };

    on_load();

    return {
        change: change
    };

})();

