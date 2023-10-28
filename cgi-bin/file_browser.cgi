#!/opt/openrvdas/venv/bin/python
"""
    cgi-bin/file_browser.cgi

    Escript that handles GET/PUT for file browser
    (for loading configurations)
"""

import cgi
import cgitb
import sys
import os
import json5 as json
import secret

# Local imports
import secret                               # noqa E402
from openrvdas_vars import OPENRVDAS_ROOT   # noqa E402
sys.path.append(OPENRVDAS_ROOT)
from server.sqlite_server_api import SQLiteServerAPI # noqa E402
from logger.utils.read_config import read_config # noqa E402

api = SQLiteServerAPI()
cgitb.enable()

##############################################################################
def handle_get():
    """ Called to handle GET method HTTP request """

    (headers, content, status) = process_get()

    if (content):
        headers.append('Content-Type: application/json')
        headers.append('Cache-Control: no-cache')

    for header in headers:
        print(header)
    print()

    if content:
        print(json.dumps(content, indent=2))
        if content.get('error', None):
            print(content, file=sys.stderr)


##############################################################################
def get_load(form):
    """ Called when the Load button is pressed in LoadCOnfig.html """

    content = {}

    html = '<div>Confirm Load?</div>'
    html = html + '<span>'
    fname = form.get('fname', 'Something is wrong')
    html = html + fname
    html = html + '</span>'
    sl_jwt = secret.short_ttl_jwt()
    html = html + '<input type="hidden" '
    html = html + 'name="CSRF Token" value="%s">' % sl_jwt
    html = html + '<input type="hidden" '
    html = html + 'name="fname" value="%s">' % fname
    html = html + '<input type="hidden" '
    html = html + 'name="verb" value="load">'
    content['html'] = html
    return ([], content, 200)


##############################################################################
def process_get():
    """ Lower level processing for GET request
        The GET method only sends JSON to the client listing
        the files and directories and optionally the text of
        a requested file.

        { 'dirs': [ 'enterprise', 'lexington'],
          'files': [ 'README.md', 'a.yaml', 'b.yaml', 'c.json' ]
        optionally:
          'text': "Text of file"
        }
    """
    # Saw an example that this works on QS, too.  I guess we can try
    content = {}
    form = {}
    fs = cgi.FieldStorage()
    for key in fs.keys():
        form[key] = fs[key].value
    print("Query = %s" % form, file=sys.stderr)

    # Get our safedir
    config = None
    try:
        # Style question:  Should we use urllib.request here?
        f = open("../js/openrvdas.json")
        config = json.load(f)
        f.close()
    except Exception as error:
        print("Error trying to load config.json: %s" % error, file=sys.stderr)
        content['ok'] = 0
        content['error'] = str(error)
        return ([], content, 451)
    safedir = config.get('safedir', '/opt/openrvdas')
    print('safedir = %s' % safedir, file=sys.stderr)

    try:
        if form.get('verb', None) == 'load':
            (headers, content, status) = get_load(form)
            return (headers, content, status)
    except Exception as err:
        print("Error trying to get_load: %s" % err, file=sys.stderr)
        content['ok'] = 0
        content['error'] = err
        return ([], content, 451)
    dirname = form.get('dir', OPENRVDAS_ROOT)

    # Validate dirname for safety
    apath = os.path.abspath(dirname)
    if not apath.startswith(safedir):
        print("rectified path (%s) does not start with safedir(%s)" % (apath, safedir), file=sys.stderr)
        content['ok'] = 0
        content['error'] = 'Cannot browse outside safety zone'
        return ([], content, 403)

    if not os.path.isdir(dirname):
        content['error'] = "Not a directory: %s" % dirname
        return ([], content, 400)

    dirs = []
    files = []
    try:
        for path in os.scandir(dirname):
            if path.name.startswith('.'):
                continue
            if path.is_file():
                files.append(path.name)
            else:
                dirs.append(path.name)
        sdirs = sorted(dirs)
        content['dirs'] = sdirs
        sfiles = sorted(files)
        content['files'] = sfiles
        content['dir'] = dirname
    except Exception as error:
        content = {}
        content['error'] = "Cannot list directory %s" % dirname
        content['exception'] = error
        return ([], content, 451)

    fname = form.get('file', None)
    if fname == "null":
        fname = None
    # FIXME:  Security:  Need to not send text of arbitrary file
    #         (Like /etc/shadow).
    if fname:
        try:
            filepath = os.path.join(dirname, fname)
            with open(filepath, 'r') as file:
                content['text'] = file.read()
        except Exception as error:
            content = {}
            content['error'] = 'Cannot read file %s' % fname
            content['exception'] = error
            return ([], content, 403)

    return ([], content, 200)


##############################################################################
def handle_post():
    """ Called when this is accessed via the POST HTTP method """

    (headers, content, status) = process_post_request()

    if content:
        headers.append("Content-Type: text/json")

    headers.append('Status: %s' % status)
    for header in headers:
        print(header)
    print()

    if content:
        print(content)
    else:
        print('{}')
    if 'error' in content:
        print(content, file=sys.stderr)


##############################################################################
def process_post_request():
    """ Lower level handler for the POST request """

    content = {}

    # Handle form fields
    form = {}
    # Convert cgi.FieldStorage to a dictionary
    fs = cgi.FieldStorage()
    for key in fs.keys():
        form[key] = fs[key].value
        print("%s = %s" % (key, form[key]), file=sys.stderr)

    fname = form.get('fname', None)
    if not fname:
        content['ok'] = 0
        content['error'] = "No filename specified"
        return ([], content, 418)
    username = secret.validate_token()
    if not username:
        content['ok'] = 0
        content['error'] = 'Not Authorized'
        return ([], content, 401)
    try:
        config = read_config(fname)
        config['config_filename'] = fname
        api.load_configuration(config)
        #config = api.get_configuration()
        # FIXME:  Log this to api.messagelog
        # print(config['cruise'], file=sys.stderr)
    except Exception as err:
        Q = "Exception in api.load_configuration(%s): %s" % (fname, err)
        content['ok'] = 'false'
        content['error'] = Q
        return ([], content, 406)
    else:
        pass
        # print("No exception loading config", file=sys.stderr)

    # FIXME: log the mode change in the API.
    content['ok'] = 'true'
    content['config_filename'] = fname
    print('Loading %s' % fname, file=sys.stderr)
    return ([], content, 200)


##############################################################################
if __name__ == "__main__":
    try:
        method = os.environ.get("REQUEST_METHOD", None)
        if method == "GET":
            handle_get()
        elif method == "POST":
            handle_post()
        else:
            handle_post()
    except Exception as err:
        # This will show up in /var/log/openrvdas/fcgiwrap_stderr.log
        print("Error processing form: %s" % err, file=sys.stderr)
        Q = "Unhandled exceptionL %s" % err
        content['ok'] = 'false'
        content['error'] = Q
        print("Content-Type: text/json")
        print("Status: 500")
        print("")
        print(content)
