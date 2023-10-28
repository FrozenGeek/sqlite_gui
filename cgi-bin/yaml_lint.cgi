#!/opt/openrvdas/venv/bin/python
"""
    cgi-bin/yaml_lint.cgi

    Runs lint on the fname given in the QueryString
    returns JSON with errors/warnings.

"""
import cgi
import cgitb
import json
import os
import subprocess
import sys
import yamllint
import yamllint.config
from os.path import dirname, realpath


cgitb.enable()


##############################################################################
def handle_get():
    """ Called to handle GET method HTTP request """

    (headers, content, status) = process_get()

    if (content):
        # What format will we use ??
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
def process_get():
    """ Lower level processing for GET request
        The GET method only sends JSON to the client listing
        the files and directories and optionally the text of
        a requested file.
     """

    # fname = form.get('fname', '/dev/null')
    # exec yamllint fname with config [x]
    # regex just the errors
    # return those in  a format that codemittor's lint will digest
    # Saw an example that this works on QS, too.  I guess we can try
    content = {}
    form = {}
    fs = cgi.FieldStorage()
    for key in fs.keys():
        form[key] = fs[key].value
    print("Query = %s" % form, file=sys.stderr)

    fname = form.get('fname', '/dev/null')
    # FIXME:  Validate fname is inside our safedir or 400 (maybe 406)

    # Run yamllint
    try:
        s = []
        yaml_config = yamllint.config.YamlLintConfig("extends: default")
        try:
            f = open(fname, 'r')
        except:
            return ([], content, 200)
        for p in yamllint.linter.run(f, yaml_config):
            mark = {
                'line': p.line,
                'column': p.column,
                'message': p.desc,
                'severity': p.level
            }
            s.append(mark)
            content['lint'] = s
    except Exception as error:
        content = {}
        content['error'] = "Cannot lint file %s" % fname
        content['exception'] = error
        return ([], content, 451)
    # Massage output
    # for line in s:
    #      """ The javascript that parses the return 
    #  found = [];
    #  // jsyaml only returns the first error, but for each error:
    #  var loc = e.mark,
    #      // js-yaml YAMLException doesn't always provide an accurate lineno
    #      // e.g., when there are multiple yaml docs
    #      // ---
    #      // ---
    #      // foo:bar
    #      from = loc ? CodeMirror.Pos(loc.line, loc.column) : CodeMirror.Pos(0, 0),
    #      to = from;
    #  found.push({ from: from, to: to, message, e.message })
    #      
    #      """
    #      """ The lint output
    #"b'/opt/openrvdas/local/usap/lmg/lmg2303_cruise.yaml",
    #"  6:81      error    line too long (86 > 80 characters)  (line-length)",
    #"  11:1      warning  missing document start \"---\"  (document-start)",
    #"  20:5      error    wrong indentation: expected 6 but found 4  (indentation)",
    #      """ 
    return ([], content, 200)


##############################################################################
def handle_post():
    """ This CGI should not be called via port """

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
    content['error'] = 'Not Authorized'
    return ([], content, 401)


##############################################################################
if __name__ == "__main__":
    method = os.environ.get("REQUEST_METHOD", None)
    try:
        if method == "GET":
            handle_get()
        elif method == "POST":
            handle_post()
        else:
            handle_get()
    except Exception as err:
        print(cgitb.html, file=sys.stderr)
        print("Error: %s" % err, file=sys.stderr)
        print("Contebt-Type: text/html")
        print()
        print(cgitb.html) 
